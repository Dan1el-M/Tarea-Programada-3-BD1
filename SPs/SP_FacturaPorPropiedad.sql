USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_FacturasPorPropiedad]    Script Date: 23/11/2025 17:09:33 ******/
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
SP que me muestras las facturas pendientes de una propiedad, las muestra ya ordenadas por la más viejas primero
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
            f.Id, f.PropiedadId, f.FechaFactura, f.FechaLimitePagar,
            f.TotalAPagarOriginal, f.TotalAPagarFinal, f.EstadoFacturaId
        FROM dbo.Factura f
        WHERE f.PropiedadId = @inNumeroFinca
          AND f.EstadoFacturaId = 1  -- pendientes
        ORDER BY f.FechaFactura, f.Id;

    END TRY
    BEGIN CATCH
        SET @outResultCode = 50053;

        INSERT dbo.DBError(
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
    END CATCH
END;
GO

