USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_DetalleFactura]    Script Date: 24/11/2025 17:31:11 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_DetalleFactura]
(
    @inNumeroFactura INT,
    @outResultCode INT OUTPUT
)

/*
Este SP recibe un número de factura y trae el detalle de esa factura:
    - qué conceptos de cobro tiene (agua, basura, impuesto, etc.)
    - cuánto se cobró por cada uno
*/

AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SET @outResultCode = 0;

        SELECT
            cc.Nombre AS NombreCC,       -- nombre real del concepto
            df.Monto  AS Monto
        FROM dbo.DetalleFactura df
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = df.ConceptoCobroId
        WHERE df.FacturaId = @inNumeroFactura
        ORDER BY df.Id;

    END TRY
    BEGIN CATCH
        SET @outResultCode = 50090;

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
            'SP_DetalleFactura'
            ,ERROR_NUMBER()
            ,ERROR_STATE()
            ,ERROR_SEVERITY()
            ,ERROR_LINE()
            ,'SP_DetalleFactura'
            ,ERROR_MESSAGE()
            , SYSDATETIME()
        );

        THROW;

    END CATCH
END
GO

