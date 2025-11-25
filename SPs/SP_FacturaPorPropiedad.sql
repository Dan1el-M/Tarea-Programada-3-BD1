USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_FacturasPorPropiedad]    Script Date: 24/11/2025 17:41:51 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_FacturasPorPropiedad]
(
    @inNumeroFinca VARCHAR(64),
    @outResultCode INT OUTPUT
)

/*
SP que me muestras las facturas  de una propiedad, las muestra ya ordenadas
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Propiedad WHERE NumeroFinca = @inNumeroFinca)
        BEGIN
            SET @outResultCode = 3;
            RETURN;
        END

        SET @outResultCode = 0;

        SELECT
            f.Id AS NumeroFactura
            , f.FechaFactura
            , f.FechaLimitePagar
            , f.TotalAPagarFinal
            , f.EstadoFacturaId
            , MAX(p.FechaPago) AS FechaPago
        FROM dbo.Factura f
        LEFT JOIN dbo.Pago p
            ON p.FacturaId = f.Id
        WHERE f.PropiedadId = @inNumeroFinca
        GROUP BY
            f.Id, f.FechaFactura, f.FechaLimitePagar,
            f.TotalAPagarFinal, f.EstadoFacturaId
        ORDER BY f.FechaFactura DESC;

    END TRY
    BEGIN CATCH
        SET @outResultCode = 50053;

        INSERT INTO dbo.DBError(
            UserName
            , Number
            , State
            , Severity
            , Line
            , [Procedure]
            , Message
            , DateTime
        )

        VALUES(
            'SP_FacturasPorPropiedad'
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_FacturasPorPropiedad'
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );

        THROW;
    END CATCH
END;
GO

