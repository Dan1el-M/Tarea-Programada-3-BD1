USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarOperacionesDesdeXMLV2]    Script Date: 24/11/2025 17:17:08 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarOperacionesDesdeXMLV2]
(
    @inXmlOperaciones XML,
    @outResultCode    INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        --1) Partir XML por fechas
        DECLARE @Fechas TABLE
        (
            Fecha DATE PRIMARY KEY,
            Nodo  XML
        );

        INSERT INTO @Fechas(Fecha, Nodo)
        SELECT
            F.value('@fecha','date') AS Fecha,
            F.query('.')            AS Nodo
        FROM @inXmlOperaciones.nodes('/Operaciones/FechaOperacion') AS T(F);

        
         --2) Iterar cronológicamente
        DECLARE
            @FechaActual DATE
            ,@FechaXml    XML
            ,@rc          INT;

        WHILE EXISTS (SELECT 1 FROM @Fechas)
        BEGIN
            BEGIN TRANSACTION;

            SELECT TOP (1)
                @FechaActual = Fecha,
                @FechaXml    = Nodo
            FROM @Fechas
            ORDER BY Fecha;

   
            --Insertar Personas (solo nuevas)
            INSERT INTO dbo.Persona
            (
                ValorDocumento
                ,Nombre
                ,Email
                ,Telefono
                ,Fecha
            )
            SELECT
                 P.value('@valorDocumento','varchar(64)')
                ,P.value('@nombre','nvarchar(128)')
                ,P.value('@email','nvarchar(128)')
                ,P.value('@telefono','varchar(32)')
                , @FechaActual

            FROM @FechaXml.nodes('/FechaOperacion/Personas/Persona') AS T(P)
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM dbo.Persona per
                WHERE per.ValorDocumento =
                      T.P.value('@valorDocumento','varchar(64)')
            );


             --Insertar Propiedades (solo nuevas)
            INSERT INTO dbo.Propiedad
            (
                 NumeroFinca
                ,NumeroMedidor
                ,MetrosCuadrados
                ,TipoUsoId
                ,TipoZonaId
                ,ValorFiscal
                ,FechaRegistro
            )
            SELECT
                 PR.value('@numeroFinca','varchar(64)')
                ,PR.value('@numeroMedidor','varchar(32)')
                ,PR.value('@metrosCuadrados','decimal(10,2)')
                ,PR.value('@tipoUsoId','int')
                ,PR.value('@tipoZonaId','int')
                ,PR.value('@valorFiscal','money')
                ,PR.value('@fechaRegistro','date')
            FROM @FechaXml.nodes('/FechaOperacion/Propiedades/Propiedad') AS T(PR)
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM dbo.Propiedad p
                WHERE p.NumeroFinca =
                      T.PR.value('@numeroFinca','varchar(64)')
            );

       
            -- PropiedadPersona (asociar / desasociar)
      
            -- Asociar
            INSERT INTO dbo.PropiedadPersona
            (
                PropiedadId
                ,PersonaId
                ,FechaInicio
                ,FechaFin
                ,TipoAsociacionId
            )
            SELECT
                p.NumeroFinca
                ,per.Id
                ,@FechaActual
                ,NULL
                ,1
            FROM @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad p
                ON p.NumeroFinca = 
                            T.M.value('@numeroFinca','varchar(64)')
            INNER JOIN dbo.Persona per
                ON per.ValorDocumento = 
                            T.M.value('@valorDocumento','varchar(64)')
            WHERE T.M.value('@tipoAsociacionId','int') = 1
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.PropiedadPersona pp
                  WHERE pp.PropiedadId = p.NumeroFinca
                    AND pp.PersonaId   = per.Id
                    AND pp.FechaFin IS NULL
              );

            -- Desasociar (cerrar intervalo)
            UPDATE pp
            SET
                pp.FechaFin         = @FechaActual,
                pp.TipoAsociacionId = 2
            FROM dbo.PropiedadPersona pp

            INNER JOIN dbo.Propiedad p
                ON p.NumeroFinca = pp.PropiedadId
            INNER JOIN dbo.Persona per
                ON per.Id = pp.PersonaId
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadPersona/Movimiento') AS T(M)
                ON p.NumeroFinca = 
                                T.M.value('@numeroFinca','varchar(64)')
               AND per.ValorDocumento = 
                                T.M.value('@valorDocumento','varchar(64)')
            WHERE T.M.value('@tipoAsociacionId','int') = 2
              AND pp.FechaFin IS NULL;


            --CCPropiedad (asignar / desasignar)

            -- Asignar CC (tipoAsociacionId = 1)
            INSERT INTO dbo.ConceptoCobroPropiedad
            (
                 PropiedadId
                ,ConceptoCobroId
                ,FechaAsociacion
            )
            SELECT
                 p.NumeroFinca
                ,cc.Id
                ,@FechaActual

            FROM @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
            INNER JOIN dbo.Propiedad p
                ON p.NumeroFinca = 
                            T.M.value('@numeroFinca','varchar(64)')
            INNER JOIN dbo.ConceptoCobro cc
                ON cc.Id = 
                        T.M.value('@idCC','int')
            WHERE T.M.value('@tipoAsociacionId','int') = 1
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.ConceptoCobroPropiedad cp
                  WHERE cp.PropiedadId     = p.NumeroFinca
                    AND cp.ConceptoCobroId = cc.Id
              );

            -- Desasignar CC (tipoAsociacionId = 2)
            DELETE cp
            FROM dbo.ConceptoCobroPropiedad cp
            INNER JOIN @FechaXml.nodes('/FechaOperacion/CCPropiedad/Movimiento') AS T(M)
                ON cp.PropiedadId = 
                                T.M.value('@numeroFinca','varchar(64)')
               AND cp.ConceptoCobroId = 
                                T.M.value('@idCC','int')
            WHERE T.M.value('@tipoAsociacionId','int') = 2;


           
            --Cambios en valor fiscal
            UPDATE p
            SET p.ValorFiscal = 
                            C.value('@nuevoValor','money')
            FROM dbo.Propiedad p
            INNER JOIN @FechaXml.nodes('/FechaOperacion/PropiedadCambio/Cambio') AS T(C)
                ON p.NumeroFinca = 
                                T.C.value('@numeroFinca','varchar(64)');


            --Procesos diarios atómicos
            EXEC dbo.SP_ProcesarLecturasDelDia
                @inFecha        = @FechaActual
                ,@inFechaXml     = @FechaXml
                ,@outResultCode  = @rc OUTPUT;

            IF (@rc <> 0)
                RAISERROR('Error en SP_ProcesarLecturasDelDia',16,1);

            EXEC dbo.SP_ProcesarPagosDelDia
                @inFecha        = @FechaActual
                ,@inFechaXml     = @FechaXml
                ,@outResultCode  = @rc OUTPUT;

            IF (@rc <> 0)
                RAISERROR('Error en SP_ProcesarPagosDelDia',16,1);

            EXEC dbo.SP_GenerarFacturasDelDia
                @inFecha        = @FechaActual
                , @outResultCode  = @rc OUTPUT;

            IF (@rc <> 0)
                RAISERROR('Error en SP_GenerarFacturasDelDia',16,1);

            EXEC dbo.SP_GenerarCortasDelDia
                @inFecha        = @FechaActual
                ,@outResultCode  = @rc OUTPUT;

            IF (@rc <> 0)
                RAISERROR('Error en SP_GenerarCortasDelDia',16,1);

            EXEC dbo.SP_GenerarReconexionesDelDia
                @inFecha        = @FechaActual
                ,@outResultCode  = @rc OUTPUT;

            IF (@rc <> 0)
                RAISERROR('Error en SP_GenerarReconexionesDelDia',16,1);

        
            --Siguiente fecha
            COMMIT TRANSACTION;

            DELETE FROM @Fechas
            WHERE Fecha = @FechaActual;
            

        END; -- WHILE

        
        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH
        
        IF @@TRANCOUNT > 0 --o este ya no va?
        ROLLBACK TRANSACTION;
        SET @outResultCode = 50002;

        INSERT INTO dbo.DBError
        (
            UserName
            ,Number
            ,State
            ,Severity
            ,Line
            ,[Procedure]
            ,Message
            ,DateTime
        )
        VALUES
        (
            'SP_CargarOperacionesDesdeXMLV2'
            ,ERROR_NUMBER()
            ,ERROR_STATE()
            ,ERROR_SEVERITY()
            ,ERROR_LINE()
            ,'SP_CargarOperacionesDesdeXMLV2'
            ,ERROR_MESSAGE()
            ,SYSDATETIME()
        );

        THROW;

    END CATCH
END;
GO

