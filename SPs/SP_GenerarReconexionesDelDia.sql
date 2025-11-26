USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarReconexionesDelDia]    Script Date: 26/11/2025 15:52:58 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_GenerarReconexionesDelDia]
(
      @inFecha       DATE
    , @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE @CortasCandidatas TABLE
        (
              OrdenCortaId INT        PRIMARY KEY
            , PropiedadId  VARCHAR(64)
            , FacturaId    INT
        );

        INSERT INTO @CortasCandidatas
        (
              OrdenCortaId
            , PropiedadId
            , FacturaId
        )
        SELECT
              oc.Id
            , oc.PropiedadId
            , oc.FacturaId
        FROM dbo.OrdenCorta AS oc
        INNER JOIN dbo.Factura AS f
            ON f.Id = oc.FacturaId
        WHERE     oc.Estado          = 1       -- corta activa
              AND f.EstadoFacturaId  = 2       -- factura ya pagada
              AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.OrdenReconexion AS r
                      WHERE     r.PropiedadId = oc.PropiedadId
                            AND r.FacturaId   = oc.FacturaId
                  );

        IF NOT EXISTS (SELECT 1 FROM @CortasCandidatas)
        BEGIN
            SET @outResultCode = 0;
            RETURN;
        END;

        BEGIN TRANSACTION;

        INSERT INTO dbo.OrdenReconexion
        (
              PropiedadId
            , FacturaId
            , FechaGenerada
            , Estado
        )
        SELECT
              c.PropiedadId
            , c.FacturaId
            , @inFecha
            , 1
        FROM @CortasCandidatas AS c;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH

        IF ( @@TRANCOUNT > 0 )
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50007;

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

