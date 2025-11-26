USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ProcesarPagosDelDia]    Script Date: 26/11/2025 15:54:51 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_ProcesarPagosDelDia]
(
      @inFecha       DATE
    , @inFechaXml    XML
    , @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        
        -- Extraer pagos desde el XML
        DECLARE @Pagos TABLE
        (
              NumeroFinca      VARCHAR(64)
            , TipoMedioPagoId  INT
            , NumeroReferencia VARCHAR(128)
        );

        INSERT INTO @Pagos
        (
              NumeroFinca
            , TipoMedioPagoId
            , NumeroReferencia
        )
        SELECT
              P.value('@numeroFinca',     'VARCHAR(64)')
            , P.value('@tipoMedioPagoId', 'INT')
            , P.value('@numeroReferencia','VARCHAR(128)')
        FROM @inFechaXml.nodes('/FechaOperacion/Pagos/Pago') AS T(P);

        -- Mapear pagos con facturas pendientes por finca
        DECLARE @PagosConFactura TABLE
        (
              NumeroFinca      VARCHAR(64)
            , TipoMedioPagoId  INT
            , NumeroReferencia VARCHAR(128)
            , FacturaId        INT
            , TotalOriginal    MONEY
            , TotalFinal       MONEY
            , FechaLimite      DATE
            , DiasMorosos      INT   NULL
            , Interes          MONEY NULL
        );

        ;WITH PagosOrdenados AS
        (
            SELECT
                  p.NumeroFinca
                , p.TipoMedioPagoId
                , p.NumeroReferencia
                , ROW_NUMBER() OVER
                  (
                      PARTITION BY p.NumeroFinca
                      ORDER BY (SELECT 1)
                  ) AS PagoNum
            FROM @Pagos AS p
        ),
        FacturasPendientes AS
        (
            SELECT
                  f.Id
                , f.PropiedadId       AS NumeroFinca
                , f.TotalAPagarOriginal
                , f.TotalAPagarFinal
                , f.FechaLimitePagar
                , ROW_NUMBER() OVER
                  (
                      PARTITION BY f.PropiedadId
                      ORDER BY     f.FechaFactura
                               ,   f.Id
                  ) AS FacturaNum
            FROM dbo.Factura AS f
            WHERE f.EstadoFacturaId = 1
        )
        INSERT INTO @PagosConFactura
        (
              NumeroFinca
            , TipoMedioPagoId
            , NumeroReferencia
            , FacturaId
            , TotalOriginal
            , TotalFinal
            , FechaLimite
        )
        SELECT
              po.NumeroFinca
            , po.TipoMedioPagoId
            , po.NumeroReferencia
            , fp.Id
            , fp.TotalAPagarOriginal
            , fp.TotalAPagarFinal
            , fp.FechaLimitePagar
        FROM PagosOrdenados AS po
        INNER JOIN FacturasPendientes AS fp
            ON     fp.NumeroFinca = po.NumeroFinca
               AND fp.FacturaNum  = po.PagoNum;

        -- Calcular morosidad e intereses
        DECLARE @IdCC_InteresesMoratorios INT;

        SELECT 
            @IdCC_InteresesMoratorios = cc.Id
        FROM dbo.ConceptoCobro AS cc
        WHERE cc.Nombre = 'InteresesMoratorios';

        UPDATE pc
        SET pc.DiasMorosos =
            CASE 
                WHEN @inFecha > pc.FechaLimite
                    THEN DATEDIFF(DAY, pc.FechaLimite, @inFecha)
                ELSE 0
            END
        FROM @PagosConFactura AS pc;

        UPDATE pc
        SET pc.Interes =
            CASE 
                WHEN pc.DiasMorosos > 0
                    THEN pc.TotalOriginal * 0.04 / 30.0 * pc.DiasMorosos
                ELSE 0
            END
        FROM @PagosConFactura AS pc;

        BEGIN TRANSACTION;

        -- Insertar detalle de intereses
        INSERT INTO dbo.DetalleFactura
        (
              FacturaId
            , ConceptoCobroId
            , Monto
            , Descripcion
        )
        SELECT
              pc.FacturaId
            , @IdCC_InteresesMoratorios
            , pc.Interes
            , 'Intereses moratorios'
        FROM @PagosConFactura AS pc
        WHERE pc.Interes > 0;

        -- Actualizar total final de factura
        UPDATE f
        SET f.TotalAPagarFinal = f.TotalAPagarFinal + pc.Interes
        FROM dbo.Factura AS f
        INNER JOIN @PagosConFactura AS pc
            ON pc.FacturaId = f.Id
        WHERE pc.Interes > 0;

        -- Insertar pagos
        INSERT INTO dbo.Pago
        (
              FacturaId
            , TipoMedioPagoId
            , FechaPago
            , MontoPagado
            , NumeroReferencia
        )
        SELECT
              pc.FacturaId
            , pc.TipoMedioPagoId
            , @inFecha
            , ( pc.TotalFinal + ISNULL(pc.Interes, 0) )
            , pc.NumeroReferencia
        FROM @PagosConFactura AS pc;

        -- Marcar facturas pagadas
        UPDATE f
        SET f.EstadoFacturaId = 2
        FROM dbo.Factura AS f
        INNER JOIN @PagosConFactura AS pc
            ON pc.FacturaId = f.Id;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH

        IF ( @@TRANCOUNT > 0 )
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50013;

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

