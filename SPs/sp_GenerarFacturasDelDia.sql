USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarFacturasDelDia]    Script Date: 23/11/2025 17:10:10 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_GenerarFacturasDelDia](
    @inFecha DATE,
    @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        ------------------------------------------------------------
        -- 1) Parámetros del sistema
        ------------------------------------------------------------
        DECLARE @DiasVenc INT =
            (SELECT TRY_CONVERT(INT, Valor)
             FROM dbo.ParametrosSistema
             WHERE Nombre = 'DiasVencimientoFactura');

        IF @DiasVenc IS NULL
            SET @DiasVenc = 15; -- por si no está en XML

        ------------------------------------------------------------
        -- 2) Propiedades que se facturan HOY
        --    Día de cobro = MIN( día(fechaRegistro), día(fin de mes de @inFecha) )
        --    Esto cubre 31 vs meses de 30/29/28.
        ------------------------------------------------------------
        DECLARE @PropsHoy TABLE(NumeroFinca VARCHAR(64) PRIMARY KEY);

        INSERT INTO @PropsHoy(NumeroFinca)
        SELECT p.NumeroFinca
        FROM dbo.Propiedad p
        WHERE
            FechaRegistro <= @inFecha
            AND 
            -- día ajustado
            (CASE 
                WHEN DAY(p.FechaRegistro) > DAY(EOMONTH(@inFecha))
                    THEN DAY(EOMONTH(@inFecha))
                ELSE DAY(p.FechaRegistro)
            END = DAY(@inFecha)
            );

        IF NOT EXISTS (SELECT 1 FROM @PropsHoy)
        BEGIN
            SET @outResultCode = 0;
            RETURN;
        END

        BEGIN TRANSACTION;

        ------------------------------------------------------------
        -- 3) Crear Factura por cada propiedad hoy
        ------------------------------------------------------------
        DECLARE @FacturasHoy TABLE(
            FacturaId INT PRIMARY KEY,
            PropiedadId VARCHAR(64)
        );

        INSERT INTO dbo.Factura(
            PropiedadId, FechaFactura, FechaLimitePagar,
            TotalAPagarOriginal, TotalAPagarFinal, EstadoFacturaId
        )
        OUTPUT inserted.Id, inserted.PropiedadId
        INTO @FacturasHoy(FacturaId, PropiedadId)
        SELECT
            ph.NumeroFinca,
            @inFecha,
            DATEADD(DAY, @DiasVenc, @inFecha),
            0, 0, 1
        FROM @PropsHoy ph;

        /* ====================== AGUA ======================
          Valor minino: 500, ValorFijoM3Adicional = 100
        */
        INSERT INTO dbo.DetalleFactura(FacturaId, ConceptoCobroId, Monto, Descripcion)
        SELECT
            f.FacturaId,
            cc.Id,
            CASE 
                WHEN (p.SaldoM3 - p.SaldoM3UltimaFactura) > ISNULL(a.ValorMinimoM3,0)
                    THEN 
                        ISNULL(a.ValorMinimo,0) +
                        ((p.SaldoM3 - p.SaldoM3UltimaFactura) - ISNULL(a.ValorMinimoM3,0))
                        * ISNULL(a.ValorFijoM3Adicional,0)
                ELSE ISNULL(a.ValorMinimo,0)
            END AS Monto,
            CONCAT('ConsumoAgua (', (p.SaldoM3 - p.SaldoM3UltimaFactura), ' m3)') AS Descripcion
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_ConsumoAgua a
            ON a.Id = cc.Id;

        -- Luego de cobrar agua, se deja en 0 para el siguiente mes
        UPDATE p
        SET p.SaldoM3UltimaFactura = p.SaldoM3
        FROM dbo.Propiedad p
        INNER JOIN @FacturasHoy f
            ON f.PropiedadId = p.NumeroFinca
        WHERE EXISTS (
            SELECT 1
            FROM dbo.ConceptoCobroPropiedad ccp
            INNER JOIN dbo.CC_ConsumoAgua a ON a.Id = ccp.ConceptoCobroId
            WHERE ccp.PropiedadId = p.NumeroFinca
        );

        /* ================== PATENTE COMERCIAL ==================
           ValorFijo / 6
        */
        INSERT INTO dbo.DetalleFactura(FacturaId, ConceptoCobroId, Monto, Descripcion)
        SELECT
            f.FacturaId,
            cc.Id,
            ISNULL(pc.ValorFijo,0) / 6.0,
            'PatenteComercial'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_PatenteComercial pc
            ON pc.Id = cc.Id;

        /* ================== IMPUESTO PROPIEDAD ==================
           (ValorFiscal * 1% ) / 12
        */
        INSERT INTO dbo.DetalleFactura(FacturaId, ConceptoCobroId, Monto, Descripcion)
        SELECT
            f.FacturaId,
            cc.Id,
            (p.ValorFiscal * ISNULL(ip.ValorPorcentual,0)) / 12.0,
            'ImpuestoPropiedad'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_ImpuestoPropiedad ip
            ON ip.Id = cc.Id;

        /* ================== RECOLECCIÓN BASURA ==================
           base 150 si <=400m2, +75 por cada 200m2 extra
           Mapeo a tus columnas:
             ValorMinimo   = 150
             ValorM2Minimo = 400
             ValorFijo     = 75  (por tramo)
        */
        INSERT INTO dbo.DetalleFactura(FacturaId, ConceptoCobroId, Monto, Descripcion)
        SELECT
            f.FacturaId,
            cc.Id,
            CASE
                WHEN p.MetrosCuadrados <= ISNULL(rb.ValorM2Minimo,0)
                    THEN ISNULL(rb.ValorMinimo,0)
                ELSE
                    ISNULL(rb.ValorMinimo,0) +
                    CEILING( (p.MetrosCuadrados - ISNULL(rb.ValorM2Minimo,0)) / 200.0 )
                    * ISNULL(rb.ValorFijo,0)
            END,
            'RecoleccionBasura'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_RecoleccionBasura rb
            ON rb.Id = cc.Id;

        /* ================== MANTENIMIENTO PARQUES ==================
           ValorFijo / 12
        */
        INSERT INTO dbo.DetalleFactura(FacturaId, ConceptoCobroId, Monto, Descripcion)
        SELECT
            f.FacturaId,
            cc.Id,
            ISNULL(mp.ValorFijo,0) / 12.0,
            'MantenimientoParques'
        FROM @FacturasHoy f
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = f.PropiedadId
        INNER JOIN dbo.ConceptoCobroPropiedad ccp
            ON ccp.PropiedadId = p.NumeroFinca
        INNER JOIN dbo.ConceptoCobro cc
            ON cc.Id = ccp.ConceptoCobroId
        INNER JOIN dbo.CC_MantenimientoParques mp
            ON mp.Id = cc.Id;

        ------------------------------------------------------------
        -- 5) Actualizar totales de Factura
        ------------------------------------------------------------
        UPDATE f
        SET
            f.TotalAPagarOriginal = d.SumMonto,
            f.TotalAPagarFinal    = d.SumMonto
        FROM dbo.Factura f
        INNER JOIN (
            SELECT FacturaId, SUM(Monto) AS SumMonto
            FROM dbo.DetalleFactura
            WHERE FacturaId IN (SELECT FacturaId FROM @FacturasHoy)
            GROUP BY FacturaId
        ) d ON d.FacturaId = f.Id;

        COMMIT;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SET @outResultCode = 50020;

        INSERT INTO dbo.DBError (
            UserName
            , Number
            , State
            , Severity
            , Line
            ,[Procedure]
            , Message
            , DateTime
        )
        VALUES (
            'SP_GenerarFacturasDelDia',
            ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            ,'SP_GenerarFacturasDelDia'
            ,ERROR_MESSAGE()
            ,SYSDATETIME()
        );
    END CATCH
END
GO

