USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarReconexionesDelDia]    Script Date: 23/11/2025 17:10:25 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_GenerarReconexionesDelDia](
    @inFecha DATE,
    @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartedTran BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRAN;
            SET @StartedTran = 1;
        END
        ELSE
        BEGIN
            SAVE TRAN SP_GenerarReconexionesDelDia;
        END

        ------------------------------------------------------
        -- MATERIALIZAR LAS CORTAS CANDIDATAS EN TABLA
        ------------------------------------------------------
        DECLARE @CortasCandidatas TABLE(
            OrdenCortaId INT,
            PropiedadId  VARCHAR(64),
            FacturaId    INT
        );

        INSERT INTO @CortasCandidatas
        SELECT
            oc.Id,
            oc.PropiedadId,
            oc.FacturaId
        FROM dbo.OrdenCorta oc
        INNER JOIN dbo.Factura f
            ON f.Id = oc.FacturaId
        WHERE oc.Estado = 1
          AND oc.FechaEjecutada IS NOT NULL
          AND f.EstadoFacturaId = 2
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.OrdenCorta oc2
                WHERE oc2.PropiedadId = oc.PropiedadId
                  AND oc2.Estado = 1
                  AND oc2.Id <> oc.Id
          )
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.OrdenReconexion r
                WHERE r.PropiedadId = oc.PropiedadId
                  AND r.FacturaId = oc.FacturaId
          )
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.Factura f2
                WHERE f2.PropiedadId = oc.PropiedadId
                  AND f2.EstadoFacturaId = 1
                  AND f2.FechaLimitePagar < @inFecha
          );

        ------------------------------------------------------
        -- 1) CREAR RECONEXIONES
        ------------------------------------------------------
        INSERT INTO dbo.OrdenReconexion(
            PropiedadId, FacturaId, FechaGenerada, Estado
        )
        SELECT
            PropiedadId,
            FacturaId,
            @inFecha,
            1
        FROM @CortasCandidatas;

        ------------------------------------------------------
        -- 2) CERRAR CORTAS
        ------------------------------------------------------
        UPDATE oc
        SET oc.Estado = 2,
            oc.FechaEjecutada = @inFecha
        FROM dbo.OrdenCorta oc
        INNER JOIN @CortasCandidatas c
            ON c.OrdenCortaId = oc.Id;

        IF @StartedTran = 1 COMMIT;

        SET @outResultCode = 0;
        RETURN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTran = 1
                ROLLBACK;
            ELSE
                ROLLBACK TRAN SP_GenerarReconexionesDelDia;
        END

        SET @outResultCode = 50040;

       INSERT dbo.DBError
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
            'SP_GenerarReconexionesDelDia',
            ERROR_NUMBER(),
            ERROR_STATE(),
            ERROR_SEVERITY(),
            ERROR_LINE(),
            'SP_GenerarReconexionesDelDia',
            ERROR_MESSAGE(),
            GETDATE()
        
        );
    END CATCH
END
GO

