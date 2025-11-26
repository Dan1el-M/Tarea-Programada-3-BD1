USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_FacturasPorPropiedad]    Script Date: 26/11/2025 15:51:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_FacturasPorPropiedad]
(
      @inNumeroFinca VARCHAR(64)
    , @outResultCode INT OUTPUT
)
/*
SP que muestra las facturas de una propiedad, ya ordenadas.
- Si la factura está PENDIENTE -> TotalAPagarFinal = base + moras + reconexión (simulados al día de hoy)
- Si la factura está PAGADA    -> TotalAPagarFinal = lo que tiene guardado la factura
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

       
        -- 1) Validar que exista la propiedad
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Propiedad AS p
            WHERE p.NumeroFinca = @inNumeroFinca
        )
        BEGIN
            SET @outResultCode = 3;
            RETURN;
        END;

 
        -- 2) Fecha "hoy" para calcular mora / reconexión
        DECLARE @FechaActual DATE = CONVERT(DATE, SYSDATETIME());


        -- 3) Base: facturas + fecha de pago (si tiene)
        ;WITH BaseFacturas AS
        (
            SELECT
                  f.Id               AS FacturaId
                , f.PropiedadId
                , f.FechaFactura
                , f.FechaLimitePagar
                , f.TotalAPagarOriginal
                , f.TotalAPagarFinal
                , f.EstadoFacturaId
                , MAX(p.FechaPago)  AS FechaPago
            FROM dbo.Factura AS f
            LEFT JOIN dbo.Pago AS p
                ON p.FacturaId = f.Id
            WHERE f.PropiedadId = @inNumeroFinca
            GROUP BY
                  f.Id
                , f.PropiedadId
                , f.FechaFactura
                , f.FechaLimitePagar
                , f.TotalAPagarOriginal
                , f.TotalAPagarFinal
                , f.EstadoFacturaId
        )
        SELECT
              b.FacturaId           AS NumeroFactura
            , b.FechaFactura
            , b.FechaLimitePagar
            , b.EstadoFacturaId
            , b.FechaPago
            , b.TotalAPagarOriginal    
            , CASE
                  -- Si NO está pendiente, devolvemos lo que ya tiene la factura
                  WHEN b.EstadoFacturaId <> 1
                      THEN b.TotalAPagarFinal

                  -- Si está pendiente, simulamos: base + moras + reconexión
                  ELSE b.TotalAPagarOriginal
                       + ISNULL(C.Moras,      0)
                       + ISNULL(C.Reconexion, 0)
              END AS TotalAPagarFinal
        FROM BaseFacturas AS b
        OUTER APPLY
        (
            SELECT
                  Moras =
                      CASE 
                          WHEN     ( b.EstadoFacturaId = 1 )
                               AND ( @FechaActual > b.FechaLimitePagar )
                          THEN
                              b.TotalAPagarOriginal * 0.04 / 30.0
                              * DATEDIFF(DAY, b.FechaLimitePagar, @FechaActual)
                          ELSE 0
                      END

                , Reconexion =
                      CASE 
                          WHEN ( b.EstadoFacturaId = 1 )
                               -- Debe tener agua:
                               AND EXISTS
                               (
                                   SELECT 1
                                   FROM dbo.Propiedad AS pr
                                   INNER JOIN dbo.TipoUsoPropiedad AS tu
                                       ON tu.Id = pr.TipoUsoId
                                   INNER JOIN dbo.ConceptoCobroPropiedad AS cp
                                       ON     cp.PropiedadId      = pr.NumeroFinca
                                          AND cp.TipoAsociacionId = 1
                                   INNER JOIN dbo.CC_ConsumoAgua AS ca
                                       ON ca.Id = cp.ConceptoCobroId
                                   WHERE     pr.NumeroFinca = b.PropiedadId
                                         AND tu.Nombre IN ('Residencial','Industrial','Comercial')
                               )
                               -- Corta activa
                               AND EXISTS
                               (
                                   SELECT 1
                                   FROM dbo.OrdenCorta AS oc
                                   WHERE     oc.PropiedadId = b.PropiedadId
                                         AND oc.Estado      = 1  
                               )
                               -- Esta factura es la última vencida pendiente al día de hoy
                               AND NOT EXISTS
                               (
                                   SELECT 1
                                   FROM dbo.Factura AS f2
                                   WHERE     f2.PropiedadId     = b.PropiedadId
                                         AND f2.EstadoFacturaId = 1
                                         AND f2.FechaLimitePagar < @FechaActual
                                         AND f2.Id <> b.FacturaId
                               )
                          THEN
                              (
                                  SELECT TOP (1) r.ValorFijo
                                  FROM dbo.CC_ReconexionAgua AS r
                              )
                          ELSE 0
                      END
        ) AS C
        ORDER BY
            b.FechaFactura DESC;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH
        SET @outResultCode = 50004;

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

