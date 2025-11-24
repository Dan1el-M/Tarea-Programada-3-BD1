USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarCortasDelDia]    Script Date: 23/11/2025 17:09:53 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_GenerarCortasDelDia](
    @inFecha DATE,
    @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        ------------------------------------------------------------
        -- 1) Leer DiasGraciaCorta desde ParametrosSistema
        ------------------------------------------------------------
        DECLARE @DiasGracia INT =
        (
            SELECT TRY_CONVERT(INT, Valor)
            FROM dbo.ParametrosSistema
            WHERE Nombre = 'DiasGraciaCorta'
        );

        IF @DiasGracia IS NULL
            SET @DiasGracia = 10;  -- respaldo por si no está cargado

        BEGIN TRANSACTION;

        ------------------------------------------------------------
        -- 2) Buscar facturas vencidas + gracia, pendientes,
        --    y escoger SOLO la más vieja por propiedad
        ------------------------------------------------------------
        ;WITH FacturasCandidatas AS (
            SELECT
                f.Id AS FacturaId,
                f.PropiedadId,
                f.FechaFactura,
                f.FechaLimitePagar,
                ROW_NUMBER() OVER(
                    PARTITION BY f.PropiedadId
                    ORDER BY f.FechaFactura, f.Id
                ) AS rn
            FROM dbo.Factura f
            WHERE f.EstadoFacturaId = 1  -- pendiente
              AND DATEADD(DAY, @DiasGracia, f.FechaLimitePagar) < @inFecha
        )
        INSERT INTO dbo.OrdenCorta(
            PropiedadId,
            FacturaId,
            FechaGenerada,
            FechaEjecutada,
            Estado
        )
        SELECT
            fc.PropiedadId,
            fc.FacturaId,
            @inFecha,
            NULL,
            1   -- pendiente
        FROM FacturasCandidatas fc
        WHERE fc.rn = 1  -- solo la más vieja por finca
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.OrdenCorta oc
                WHERE oc.PropiedadId = fc.PropiedadId
                  AND oc.Estado = 1 -- ya hay una corta pendiente
          );

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SET @outResultCode = 50030;

        INSERT INTO dbo.DBError(
            UserName, Number, State, Severity, Line,
            [Procedure], Message, DateTime
        )
        VALUES(
            'SP_GenerarCortasDelDia',
            ERROR_NUMBER(), ERROR_STATE(), ERROR_SEVERITY(), ERROR_LINE(),
            'SP_GenerarCortasDelDia',
            ERROR_MESSAGE(), SYSDATETIME()
        );
    END CATCH
END;
GO

