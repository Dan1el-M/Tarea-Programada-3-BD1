USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarOperacionesDesdeXML]    Script Date: 26/11/2025 15:50:50 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarOperacionesDesdeXML]
(
      @inXmlOperaciones XML
    , @outResultCode    INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY


        -- 1) Partir XML por fechas
        DECLARE @Fechas TABLE(Fecha DATE PRIMARY KEY, Nodo  XML);

        INSERT INTO @Fechas(Fecha, Nodo)
        SELECT
              F.value('@fecha','date') AS Fecha
            , F.query('.')             AS Nodo
        FROM @inXmlOperaciones.nodes('/Operaciones/FechaOperacion') AS T(F);


        -- 2) Variables de trabajo por fecha
        DECLARE
              @FechaActual DATE
            , @FechaXml    XML
            , @rc          INT;

        WHILE EXISTS (SELECT 1 FROM @Fechas)
        BEGIN

            -- Tomar la fecha más antigua
            SELECT TOP (1)
                  @FechaActual = F.Fecha
                , @FechaXml    = F.Nodo
            FROM @Fechas AS F
            ORDER BY F.Fecha;


            -- PERSONAS (solo nuevas)
            INSERT INTO dbo.Persona
            (
                  ValorDocumento
                , Nombre
                , Email
                , Telefono
                , Fecha
            )
            SELECT
                  P.value('@valorDocumento','VARCHAR(64)')
                , P.value('@nombre','NVARCHAR(128)')
                , P.value('@email','NVARCHAR(128)')
                , P.value('@telefono','VARCHAR(32)')
                , @FechaActual
            FROM @FechaXml.nodes('/FechaOperacion/Personas/Persona') AS T(P)
            LEFT JOIN dbo.Persona AS per
                ON per.ValorDocumento = P.value('@valorDocumento','VARCHAR(64)')
            WHERE per.ValorDocumento IS NULL;


            -- PROPIEDADES (solo nuevas)
            INSERT INTO dbo.Propiedad
            (
                  NumeroFinca
                , NumeroMedidor
                , MetrosCuadrados
                , TipoUsoId
                , TipoZonaId
                , ValorFiscal
                , FechaRegistro
            )
            SELECT
                  PR.value('@numeroFinca','VARCHAR(64)')
                , PR.value('@numeroMedidor','VARCHAR(32)')
                , PR.value('@metrosCuadrados','DECIMAL(10,2)')
                , PR.value('@tipoUsoId','INT')
                , PR.value('@tipoZonaId','INT')
                , PR.value('@valorFiscal','MONEY')
                , PR.value('@fechaRegistro','DATE')
            FROM @FechaXml.nodes('/FechaOperacion/Propiedades/Propiedad') AS T(PR)
            LEFT JOIN dbo.Propiedad AS p
                ON p.NumeroFinca = PR.value('@numeroFinca','VARCHAR(64)')
            WHERE p.NumeroFinca IS NULL;


            --  PROPIEDADPERSONA (asociar / desasociar)
            -- Asociar
            INSERT INTO dbo.PropiedadPersona
            (
                  PropiedadId
                , PersonaId
                , FechaInicio
                , FechaFin
                , TipoAsociacionId
            )
            SELECT
                  p.NumeroFinca
                , per.Id
                , @FechaActual
                , NULL
                , 1
            FROM @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad AS p
                ON p.NumeroFinca =
                       M.value('@numeroFinca','VARCHAR(64)')
            INNER JOIN dbo.Persona AS per
                ON per.ValorDocumento =
                       M.value('@valorDocumento','VARCHAR(64)')
            WHERE ( M.value('@tipoAsociacionId','INT') = 1 )
              AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.PropiedadPersona AS pp
                      WHERE     pp.PropiedadId = p.NumeroFinca
                            AND pp.PersonaId   = per.Id
                            AND pp.FechaFin IS NULL
                  );

            -- Desasociar (cerrar intervalo)
            UPDATE pp
            SET
                  pp.FechaFin         = @FechaActual
                , pp.TipoAsociacionId = 2
            FROM dbo.PropiedadPersona AS pp
            INNER JOIN dbo.Propiedad AS p
                ON p.NumeroFinca = pp.PropiedadId
            INNER JOIN dbo.Persona AS per
                ON per.Id = pp.PersonaId
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
                ON     p.NumeroFinca =
                           M.value('@numeroFinca','VARCHAR(64)')
                   AND per.ValorDocumento =
                           M.value('@valorDocumento','VARCHAR(64)')
            WHERE     ( M.value('@tipoAsociacionId','INT') = 2 )
                  AND ( pp.FechaFin IS NULL );



            -- CCPropiedad (asignar / desasignar)
            -- Asignar CC (tipoAsociacionId = 1)
            INSERT INTO dbo.ConceptoCobroPropiedad
            (
                  PropiedadId
                , ConceptoCobroId
                , FechaAsociacion
                , TipoAsociacionId
            )
            SELECT
                  p.NumeroFinca
                , cc.Id
                , @FechaActual
                , 1
            FROM @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad AS p
                ON p.NumeroFinca =
                       M.value('@numeroFinca','VARCHAR(64)')
            INNER JOIN dbo.ConceptoCobro AS cc
                ON cc.Id =
                       M.value('@idCC','INT')
            WHERE ( M.value('@tipoAsociacionId','INT') = 1 )
              AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.ConceptoCobroPropiedad AS cp
                      WHERE     cp.PropiedadId     = p.NumeroFinca
                            AND cp.ConceptoCobroId = cc.Id
                  );

            -- Desasignar CC (tipoAsociacionId = 2)
            UPDATE cp
            SET cp.TipoAsociacionId = 2
            FROM dbo.ConceptoCobroPropiedad AS cp
            INNER JOIN @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
                ON     cp.PropiedadId =
                           M.value('@numeroFinca','VARCHAR(64)')
                   AND cp.ConceptoCobroId =
                           M.value('@idCC','INT')
            WHERE ( M.value('@tipoAsociacionId','INT') = 2 );


            --Cambios en valor fiscal
            UPDATE p
            SET p.ValorFiscal =
                    C.value('@nuevoValor','MONEY')
            FROM dbo.Propiedad AS p
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadCambio/Cambio') AS T(C)
                ON p.NumeroFinca =
                       C.value('@numeroFinca','VARCHAR(64)');


            --  Procesos diarios atómicos
            EXEC dbo.SP_ProcesarLecturasDelDia
                  @inFecha        = @FechaActual
                , @inFechaXml    = @FechaXml
                , @outResultCode = @rc OUTPUT;

            IF ( @rc <> 0 )
                RAISERROR('Error en SP_ProcesarLecturasDelDia',16,1);



            -- Procesar pagos del día con pagarFacturaAdmin

            DECLARE
                  @NumeroFincaPago      VARCHAR(64)
                , @TipoMedioPagoId      INT
                , @NumeroReferenciaPago VARCHAR(128);

            DECLARE @PagosDia TABLE
            (
                  NumeroFinca      VARCHAR(64)
                , TipoMedioPagoId  INT
                , NumeroReferencia VARCHAR(128)
            );

            INSERT INTO @PagosDia
            (
                  NumeroFinca
                , TipoMedioPagoId
                , NumeroReferencia
            )
            SELECT
                  P.value('@numeroFinca',      'VARCHAR(64)')
                , P.value('@tipoMedioPagoId',  'INT')
                , P.value('@numeroReferencia', 'VARCHAR(128)')
            FROM @FechaXml.nodes('/FechaOperacion/Pagos/Pago') AS T(P);

            WHILE EXISTS (SELECT 1 FROM @PagosDia)
            BEGIN
                SELECT TOP (1)
                      @NumeroFincaPago      = NumeroFinca
                    , @TipoMedioPagoId      = TipoMedioPagoId
                    , @NumeroReferenciaPago = NumeroReferencia
                FROM @PagosDia
                ORDER BY NumeroFinca, NumeroReferencia;

                EXEC dbo.SP_PagarFacturaAdmin
                      @inNumeroFinca      = @NumeroFincaPago
                    , @inTipoMedioPagoId  = @TipoMedioPagoId
                    , @inNumeroReferencia = @NumeroReferenciaPago
                    , @inFechaPago        = @FechaActual
                    , @outResultCode      = @rc OUTPUT;

                IF ( @rc <> 0 )
                    RAISERROR('Error en SP_PagarFacturaAdmin',16,1);

                DELETE FROM @PagosDia
                WHERE     NumeroFinca      = @NumeroFincaPago
                      AND TipoMedioPagoId  = @TipoMedioPagoId
                      AND NumeroReferencia = @NumeroReferenciaPago;
            END;



            -- Facturas, cortas y reconexiones del día
            EXEC dbo.SP_GenerarReconexionesDelDia
                  @inFecha        = @FechaActual
                , @outResultCode = @rc OUTPUT;

            IF ( @rc <> 0 )
                RAISERROR('Error en SP_GenerarReconexionesDelDia',16,1);


            DECLARE @TieneUsosResidenciales BIT = 0;

            SELECT
                @TieneUsosResidenciales =
                    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
            FROM @FechaXml.nodes('/FechaOperacion/Propiedades/Propiedad') AS T(PR)
            WHERE PR.value('@tipoUsoId','INT') IN (1, 2, 3); -- Residencial, Industrial, Comercial

            IF ( @TieneUsosResidenciales = 1 )
            BEGIN
                EXEC dbo.SP_GenerarCortasDelDia
                      @inFecha        = @FechaActual
                    , @outResultCode = @rc OUTPUT;

                IF ( @rc <> 0 )
                    RAISERROR('Error en SP_GenerarCortasDelDia',16,1);
            END;

            EXEC dbo.SP_GenerarFacturasDelDia
                  @inFecha        = @FechaActual
                , @outResultCode = @rc OUTPUT;

            IF ( @rc <> 0 )
                RAISERROR('Error en SP_GenerarFacturasDelDia',16,1);



            --  Siguiente fecha
            DELETE FROM @Fechas
            WHERE Fecha = @FechaActual;
        END; -- WHILE


        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH
        SET @outResultCode = 50002;

        INSERT INTO dbo.DBError
        (
              UserName
            , Number
            , State
            , Severity
            , Line
            , [Procedure]
            , Message
            , DateTime
        )
        VALUES
        (
              SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );

        THROW;
    END CATCH;
END;
GO

