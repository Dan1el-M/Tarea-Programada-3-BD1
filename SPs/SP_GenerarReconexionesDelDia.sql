USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarReconexionesDelDia]    Script Date: 24/11/2025 19:11:47 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_GenerarReconexionesDelDia]
(
     @inFecha        DATE
    ,@outResultCode  INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartedTran BIT = 0;

    BEGIN TRY

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @StartedTran = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION SP_GenerarReconexionesDelDia;
        END

        -- 1) Materializar cortas candidatas
        DECLARE @CortasCandidatas TABLE
        (
             OrdenCortaId INT
            ,PropiedadId  VARCHAR(64)
            ,FacturaId    INT
        );

        INSERT INTO @CortasCandidatas
        (
             OrdenCortaId
            ,PropiedadId
            ,FacturaId
        )
        SELECT
             oc.Id
            ,oc.PropiedadId
            ,oc.FacturaId
        FROM dbo.OrdenCorta oc
        INNER JOIN dbo.Factura f
            ON f.Id = oc.FacturaId
        WHERE oc.Estado = 1
          AND oc.FechaEjecutada IS NOT NULL
          AND f.EstadoFacturaId = 2
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.OrdenCorta oc2
              WHERE oc2.PropiedadId = oc.PropiedadId
                AND oc2.Estado = 1
                AND oc2.Id <> oc.Id
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.OrdenReconexion r
              WHERE r.PropiedadId = oc.PropiedadId
                AND r.FacturaId = oc.FacturaId
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.Factura f2
              WHERE f2.PropiedadId = oc.PropiedadId
                AND f2.EstadoFacturaId = 1
                AND f2.FechaLimitePagar < @inFecha
          );

        -- 2) Crear reconexiones
        INSERT INTO dbo.OrdenReconexion
        (
             PropiedadId
            ,FacturaId
            ,FechaGenerada
            ,Estado
        )
        SELECT
             PropiedadId
            ,FacturaId
            ,@inFecha
            ,1
        FROM @CortasCandidatas;

  
        -- 3) Cerrar cortas asociadas
        UPDATE oc
        SET
             oc.Estado         = 2
            ,oc.FechaEjecutada = @inFecha
        FROM dbo.OrdenCorta oc
        INNER JOIN @CortasCandidatas c
            ON c.OrdenCortaId = oc.Id;


        -- 4) Commit si abrimos la transacción aquí
        IF @StartedTran = 1
            COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTran = 1
                ROLLBACK TRANSACTION;
            ELSE
                ROLLBACK TRANSACTION SP_GenerarReconexionesDelDia;
        END

        SET @outResultCode = 50040;

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
             'SP_GenerarReconexionesDelDia'
            ,ERROR_NUMBER()
            ,ERROR_STATE()
            ,ERROR_SEVERITY()
            ,ERROR_LINE()
            ,'SP_GenerarReconexionesDelDia'
            ,ERROR_MESSAGE()
            ,SYSDATETIME()
        );

        THROW;
    END CATCH
END
GO

