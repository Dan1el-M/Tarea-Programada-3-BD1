USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarFacturasDelDia]    Script Date: 24/11/2025 20:57:08 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_GenerarFacturasDelDia]
(
      @inFecha       DATE
    , @outResultCode INT OUTPUT
)
/*
SP que genera las facturas del día para todas las propiedades cuando día de cobro coincide
con la fecha actual. 

Calcula los conceptos de cobro asociados  y actualiza los totales de la factura.
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY


        DECLARE @DiasVenc INT =
        (
            SELECT TRY_CONVERT(INT, Valor)
            FROM dbo.ParametrosSistema
            WHERE Nombre = 'DiasVencimientoFactura'
        );

        IF @DiasVenc IS NULL
            SET @DiasVenc = 15;


        -- Propiedades que se facturan hoy  
        DECLARE @PropsHoy TABLE (NumeroFinca VARCHAR(64) PRIMARY KEY);

        INSERT INTO @PropsHoy (NumeroFinca)
        SELECT p.NumeroFinca
        FROM dbo.Propiedad p
        WHERE p.FechaRegistro <= @inFecha
          AND 
            (
                CASE
                    WHEN DAY(p.FechaRegistro) > DAY(EOMONTH(@inFecha))
                        THEN DAY(EOMONTH(@inFecha))
                    ELSE DAY(p.FechaRegistro)
                END
                = DAY(@inFecha)
            );

        IF NOT EXISTS (SELECT 1 FROM @PropsHoy)
        BEGIN
            SET @outResultCode = 0;
            RETURN;
        END

        BEGIN TRANSACTION;


        --  Crear facturas del día
        DECLARE @FacturasHoy TABLE
        (
              FacturaId   INT PRIMARY KEY
            , PropiedadId VARCHAR(64)
        );

        INSERT INTO dbo.Factura
        (
              PropiedadId
            , FechaFactura
            , FechaLimitePagar
            , TotalAPagarOriginal
            , TotalAPagarFinal
            , EstadoFacturaId
        )
        OUTPUT inserted.Id, inserted.PropiedadId
        INTO @FacturasHoy (FacturaId, PropiedadId)
        SELECT
              ph.NumeroFinca
            , @inFecha
            , DATEADD(DAY, @DiasVenc, @inFecha)
            , 0
            , 0
            , 1
        FROM @PropsHoy ph;


        --  Consumo Agua
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              f.FacturaId
            , cc.Id
            , CASE 
                WHEN (p.SaldoM3 - p.SaldoM3UltimaFactura) > ISNULL(a.ValorMinimoM3,0)
                    THEN 
                        ISNULL(a.ValorMinimo,0) +
                        ((p.SaldoM3 - p.SaldoM3UltimaFactura) - ISNULL(a.ValorMinimoM3,0))
                        * ISNULL(a.ValorFijoM3Adicional,0)
                ELSE ISNULL(a.ValorMinimo,0)
              END
            , CONCAT('ConsumoAgua (', (p.SaldoM3 - p.SaldoM3UltimaFactura), ' m3)')
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_ConsumoAgua a
            ON a.Id = cc.Id;

        -- Reset saldos para próximo mes
        UPDATE p
        SET p.SaldoM3UltimaFactura = p.SaldoM3
        FROM dbo.Propiedad p
        INNER JOIN @FacturasHoy f
            ON f.PropiedadId = p.NumeroFinca
        WHERE EXISTS (
            SELECT 1
            FROM dbo.ConceptoCobroPropiedad ccp
            INNER JOIN dbo.CC_ConsumoAgua a
                ON a.Id = ccp.ConceptoCobroId
            WHERE ccp.PropiedadId = p.NumeroFinca
        );


        --  Patente Comercial
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              f.FacturaId
            , cc.Id
            , ISNULL(pc.ValorFijo,0) / 6.0
            , 'PatenteComercial'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_PatenteComercial pc
            ON pc.Id = cc.Id;

        
        -- Impuesto Propiedad
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              f.FacturaId
            , cc.Id
            , (p.ValorFiscal * ISNULL(ip.ValorPorcentual,0)) / 12.0
            , 'ImpuestoPropiedad'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_ImpuestoPropiedad ip
            ON ip.Id = cc.Id;

        --  Recolección Basura
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              f.FacturaId
            , cc.Id
            , CASE
                WHEN p.MetrosCuadrados <= ISNULL(rb.ValorM2Minimo,0)
                    THEN ISNULL(rb.ValorMinimo,0)
                ELSE
                    ISNULL(rb.ValorMinimo,0) +
                    CEILING( (p.MetrosCuadrados - ISNULL(rb.ValorM2Minimo,0)) / 200.0 )
                    * ISNULL(rb.ValorFijo,0)
              END
            , 'RecoleccionBasura'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_RecoleccionBasura rb
            ON rb.Id = cc.Id;

        --Mantenimiento Parques
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              f.FacturaId
            , cc.Id
            , ISNULL(mp.ValorFijo,0) / 12.0
            , 'MantenimientoParques'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_MantenimientoParques mp
            ON mp.Id = cc.Id;


        -- Actualizar totales
        UPDATE f
        SET
              f.TotalAPagarOriginal = d.SumMonto
            , f.TotalAPagarFinal    = d.SumMonto
        FROM dbo.Factura f
        INNER JOIN
        (
            SELECT 
                  FacturaId
                , SUM(Monto) AS SumMonto
            FROM dbo.DetalleFactura
            WHERE FacturaId IN (SELECT FacturaId FROM @FacturasHoy)
            GROUP BY FacturaId
        ) d ON d.FacturaId = f.Id;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50020;

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
              'SP_GenerarFacturasDelDia'
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_GenerarFacturasDelDia'
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );

        THROW;

    END CATCH
END
GO

