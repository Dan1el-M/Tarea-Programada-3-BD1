USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarOperacionesDesdeXML]    Script Date: 20/11/2025 00:01:01 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarOperacionesDesdeXML]
(
    @inXmlOperaciones XML,       -- XML con el contenido de xmlUltimo.xml
    @outResultCode    INT OUTPUT -- 0 = OK, otro = error
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        --------------------------------------------------------------------
        -- 0. PREPARAR UNA TABLA CON CADA <FechaOperacion> Y SU FECHA
        --    La idea es: insertar todas las fechas, y luego irlas
        --    procesando en orden cronológico con un WHILE (sin cursores).
        --------------------------------------------------------------------
        DECLARE @Fechas TABLE
        (
            Fecha DATE PRIMARY KEY,
            Nodo  XML         -- fragmento XML de esa <FechaOperacion>
        );

        INSERT INTO @Fechas(Fecha, Nodo)
        SELECT
            F.value('@fecha','date')           AS Fecha,
            F.query('.')                       AS Nodo
        FROM @inXmlOperaciones.nodes('/Operaciones/FechaOperacion') AS T(F);

        --------------------------------------------------------------------
        -- 1. VARIABLES PARA EL BUCLE
        --------------------------------------------------------------------
        DECLARE @FechaActual DATE;
        DECLARE @FechaXml    XML;

        --------------------------------------------------------------------
        -- 2. BUCLE: MIENTRAS HAYA FECHAS PENDIENTES POR PROCESAR
        --------------------------------------------------------------------
        WHILE EXISTS (SELECT 1 FROM @Fechas)
        BEGIN
            ---------------------------------------------------------------
            -- Tomamos la fecha menor (orden cronológico) y su fragmento
            ---------------------------------------------------------------
            SELECT TOP (1)
                   @FechaActual = Fecha,
                   @FechaXml    = Nodo
            FROM @Fechas
            ORDER BY Fecha;

            ----------------------------------------------------------------
            -- 2.1 PERSONAS
            --    <Personas><Persona .../></Personas>
            --    Insertamos sólo las que no existan aún por ValorDocumento.
            ----------------------------------------------------------------
            INSERT INTO dbo.Persona
            (
                ValorDocumento,
                Nombre,
                Email,
                Telefono,
                Fecha
            )
            SELECT
                P.value('@valorDocumento','varchar(64)')   AS ValorDocumento,
                P.value('@nombre','nvarchar(128)')         AS Nombre,
                P.value('@email','nvarchar(128)')          AS Email,
                P.value('@telefono','varchar(32)')         AS Telefono,
                @FechaActual                              AS Fecha
            FROM @FechaXml.nodes('/FechaOperacion/Personas/Persona') AS T(P)
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM dbo.Persona per
                WHERE per.ValorDocumento =
                      T.P.value('@valorDocumento','varchar(64)')
            );

            ----------------------------------------------------------------
            -- 2.2 PROPIEDADES
            --    <Propiedades><Propiedad .../></Propiedades>
            --    Insertamos si no existe la finca.
            ----------------------------------------------------------------
            INSERT INTO dbo.Propiedad
            (
                NumeroFinca,
                NumeroMedidor,
                MetrosCuadrados,
                TipoUsoId,
                TipoZonaId,
                ValorFiscal,
                FechaRegistro
            )
            SELECT
                PR.value('@numeroFinca','varchar(64)')        AS NumeroFinca,
                PR.value('@numeroMedidor','varchar(32)')      AS NumeroMedidor,
                PR.value('@metrosCuadrados','decimal(10,2)')  AS MetrosCuadrados,
                PR.value('@tipoUsoId','int')                  AS TipoUsoId,
                PR.value('@tipoZonaId','int')                 AS TipoZonaId,
                PR.value('@valorFiscal','money')              AS ValorFiscal,
                PR.value('@fechaRegistro','date')             AS FechaRegistro
            FROM @FechaXml.nodes('/FechaOperacion/Propiedades/Propiedad') AS T(PR)
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM dbo.Propiedad p
                WHERE p.NumeroFinca = T.PR.value('@numeroFinca','varchar(64)')
            );

            ----------------------------------------------------------------
            -- 2.3 MOVIMIENTOS PROPIEDAD-PERSONA
            --    <PropiedadPersona><Movimiento .../></PropiedadPersona>
            --    tipoAsociacionId=1 => asociar (nueva fila con FechaInicio)
            --    tipoAsociacionId=2 => desasociar (cerrar intervalo: FechaFin)
            ----------------------------------------------------------------

            -- 2.3.1 Asociar (tipoAsociacionId=1)
            INSERT INTO dbo.PropiedadPersona
            (
                PropiedadId,
                PersonaId,
                FechaInicio,
                FechaFin,
                TipoAsociacionId
            )
            SELECT
                p.Id                            AS PropiedadId,
                per.Id                          AS PersonaId,
                @FechaActual                    AS FechaInicio,
                NULL                            AS FechaFin,
                1                               AS TipoAsociacionId
            FROM @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad p
                ON p.NumeroFinca = T.M.value('@numeroFinca','varchar(64)')
            INNER JOIN dbo.Persona per
                ON per.ValorDocumento = T.M.value('@valorDocumento','varchar(64)')
            WHERE T.M.value('@tipoAsociacionId','int') = 1
              AND NOT EXISTS
              (
                  -- Evitamos duplicar una asociación ya activa
                  SELECT 1
                  FROM dbo.PropiedadPersona pp
                  WHERE pp.PropiedadId = p.Id
                    AND pp.PersonaId   = per.Id
                    AND pp.FechaFin IS NULL
              );

            -- 2.3.2 Desasociar (tipoAsociacionId=2)
            --       Se busca la relación activa (FechaFin IS NULL) y se cierra.
            UPDATE pp
            SET
                pp.FechaFin        = @FechaActual,
                pp.TipoAsociacionId = 2
            FROM dbo.PropiedadPersona pp
            INNER JOIN dbo.Propiedad p
                ON p.Id = pp.PropiedadId
            INNER JOIN dbo.Persona per
                ON per.Id = pp.PersonaId
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
                ON p.NumeroFinca =
                   T.M.value('@numeroFinca','varchar(64)')
               AND per.ValorDocumento =
                   T.M.value('@valorDocumento','varchar(64)')
            WHERE T.M.value('@tipoAsociacionId','int') = 2
              AND pp.FechaFin IS NULL;

            ----------------------------------------------------------------
            -- 2.4 MOVIMIENTOS CONCEPTOS DE COBRO - PROPIEDAD
            --    <CCPropiedad><Movimiento .../></CCPropiedad>
            --    tipoAsociacionId=1 => asignar CC
            --    tipoAsociacionId=2 => desasignar CC
            ----------------------------------------------------------------

            -- 2.4.1 Asignar CC (alta o re-activación)
            INSERT INTO dbo.ConceptoCobroPropiedad
            (
                PropiedadId,
                ConceptoCobroId,
                FechaAsociacion,
                Activo
            )
            SELECT
                p.Id              AS PropiedadId,
                cc.Id             AS ConceptoCobroId,
                @FechaActual      AS FechaAsociacion,
                1                 AS Activo
            FROM @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad p
                ON p.NumeroFinca = T.M.value('@numeroFinca','varchar(64)')
            INNER JOIN dbo.ConceptoCobro cc
                ON cc.Id = T.M.value('@idCC','int')
            WHERE T.M.value('@tipoAsociacionId','int') = 1
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.ConceptoCobroPropiedad cp
                  WHERE cp.PropiedadId     = p.Id
                    AND cp.ConceptoCobroId = cc.Id
              );

            -- 2.4.2 Desasignar CC (marcar Activo=0)
            UPDATE cp
            SET cp.Activo = 0
            FROM dbo.ConceptoCobroPropiedad cp
            INNER JOIN dbo.Propiedad p
                ON p.Id = cp.PropiedadId
            INNER JOIN dbo.ConceptoCobro cc
                ON cc.Id = cp.ConceptoCobroId
            INNER JOIN @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
                ON p.NumeroFinca = T.M.value('@numeroFinca','varchar(64)')
               AND cc.Id         = T.M.value('@idCC','int')
            WHERE T.M.value('@tipoAsociacionId','int') = 2
              AND cp.Activo = 1;

            ----------------------------------------------------------------
            -- 2.5 LECTURAS DE MEDIDOR
            --    <LecturasMedidor><Lectura ... /></LecturasMedidor>
            ----------------------------------------------------------------
            INSERT INTO dbo.LecturaMedidor
            (
                NumeroMedidor,
                TipoMovimientoId,
                FechaLectura,
                Valor
            )
            SELECT
                L.value('@numeroMedidor','varchar(32)')       AS NumeroMedidor,
                L.value('@tipoMovimientoId','int')            AS TipoMovimientoId,
                @FechaActual                                  AS FechaLectura,
                L.value('@valor','decimal(10,2)')             AS Valor
            FROM @FechaXml.nodes('/FechaOperacion/LecturasMedidor/Lectura') AS T(L);

            ----------------------------------------------------------------
            -- 2.6 CAMBIOS DE VALOR FISCAL DE PROPIEDAD
            --    <PropiedadCambio><Cambio numeroFinca="..." nuevoValor="..."/>
            ----------------------------------------------------------------
            UPDATE p
            SET p.ValorFiscal = C.value('@nuevoValor','money')
            FROM dbo.Propiedad p
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadCambio/Cambio') AS T(C)
                ON p.NumeroFinca = T.C.value('@numeroFinca','varchar(64)');

            ----------------------------------------------------------------
            -- 2.7 PAGOS
            --    <Pagos><Pago numeroFinca="..." tipoMedioPagoId="..." 
            --          numeroReferencia="..."/></Pagos>
            --
            --    Regla simple usada aquí:
            --      - Se busca la factura PENDIENTE más antigua de esa finca.
            --      - Se inserta un pago por el monto total de esa factura.
            --      - Se marca la factura como Pagada (EstadoFacturaId = 2).
            --
            --    Si aún no hay facturas para esa finca, el pago se ignora.
            --    (AJUSTA ESTO si tu lógica del proyecto es distinta).
            ----------------------------------------------------------------
            ;WITH PagosXml AS
            (
                SELECT
                    P.value('@numeroFinca','varchar(64)')     AS NumeroFinca,
                    P.value('@tipoMedioPagoId','int')         AS TipoMedioPagoId,
                    P.value('@numeroReferencia','varchar(128)') AS NumeroReferencia
                FROM @FechaXml.nodes('/FechaOperacion/Pagos/Pago') AS T(P)
            )
            INSERT INTO dbo.Pago
            (
                FacturaId,
                TipoMedioPagoId,
                FechaPago,
                MontoPagado,
                NumeroReferencia
            )
            SELECT
                F.Id                       AS FacturaId,
                PX.TipoMedioPagoId,
                @FechaActual              AS FechaPago,
                F.TotalAPagarFinal        AS MontoPagado,
                PX.NumeroReferencia
            FROM PagosXml PX
            CROSS APPLY
            (
                SELECT TOP (1) f.Id, f.TotalAPagarFinal
                FROM dbo.Factura f
                INNER JOIN dbo.Propiedad p
                    ON p.Id = f.PropiedadId
                WHERE p.NumeroFinca = PX.NumeroFinca
                  AND f.EstadoFacturaId = 1   -- Pendiente
                ORDER BY f.FechaFactura, f.Id -- más antigua primero
            ) AS F;

            -- Marcar como pagadas las facturas a las que se aplicó un pago en esta fecha
            UPDATE f
            SET f.EstadoFacturaId = 2
            FROM dbo.Factura f
            INNER JOIN dbo.Pago pg
                ON pg.FacturaId = f.Id
            WHERE pg.FechaPago = @FechaActual;  -- sólo las de esta iteración

            ----------------------------------------------------------------
            -- 2.8 ELIMINAR LA FECHA YA PROCESADA Y CONTINUAR CON LA SIGUIENTE
            ----------------------------------------------------------------
            DELETE FROM @Fechas
            WHERE Fecha = @FechaActual;
        END; -- WHILE

        --------------------------------------------------------------------
        -- ÉXITO
        --------------------------------------------------------------------
        SET @outResultCode = 0;
        RETURN;
    END TRY
    BEGIN CATCH
        --------------------------------------------------------------------
        -- ERROR: registramos en DBError y devolvemos código
        --------------------------------------------------------------------
        SET @outResultCode = 50002;  -- código de error de este SP

        INSERT INTO dbo.DBError
        (
            UserName,
            Number,
            State,
            Severity,
            Line,
            [Procedure],
            Message,
            DateTime
        )
        VALUES
        (
            'SP_CargarOperacionesDesdeXML',
            ERROR_NUMBER(),
            ERROR_STATE(),
            ERROR_SEVERITY(),
            ERROR_LINE(),
            'SP_CargarOperacionesDesdeXML',
            ERROR_MESSAGE(),
            GETDATE()
        );
    END CATCH;
END;
GO

