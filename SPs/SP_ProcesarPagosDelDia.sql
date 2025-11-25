USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ProcesarPagosDelDia]    Script Date: 24/11/2025 20:49:25 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_ProcesarPagosDelDia]
(
     @inFecha        DATE
    ,@inFechaXml     XML
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
            SAVE TRANSACTION SP_ProcesarPagosDelDia;
        END


        -- 1) Extraer pagos
        DECLARE @Pagos TABLE
        (
             NumeroFinca       VARCHAR(64)
            ,TipoMedioPagoId   INT
            ,NumeroReferencia  VARCHAR(128)
        );

        INSERT INTO @Pagos
        (
             NumeroFinca
            ,TipoMedioPagoId
            ,NumeroReferencia
        )
        SELECT
             P.value('@numeroFinca','varchar(64)')
            ,P.value('@tipoMedioPagoId','int')
            ,P.value('@numeroReferencia','varchar(128)')
        FROM @inFechaXml.nodes('/FechaOperacion/Pagos/Pago') AS T(P);


        -- 2) Mapear pagos con facturas pendientes por finca
        DECLARE @PagosConFactura TABLE
        (
             NumeroFinca        VARCHAR(64)
            ,TipoMedioPagoId    INT
            ,NumeroReferencia   VARCHAR(128)
            ,FacturaId          INT
            ,TotalOriginal      MONEY
            ,TotalFinal         MONEY
            ,FechaLimite        DATE
            ,DiasMorosos        INT    NULL
            ,Interes            MONEY  NULL
        );

        ;WITH PagosOrdenados AS
        (
            SELECT
                 p.NumeroFinca
                ,p.TipoMedioPagoId
                ,p.NumeroReferencia
                ,ROW_NUMBER() OVER
                (
                    PARTITION BY p.NumeroFinca
                    ORDER BY (SELECT 1)
                ) AS PagoNum
            FROM @Pagos p
        ),
        FacturasPendientes AS
        (
            SELECT
                 f.Id
                ,f.PropiedadId AS NumeroFinca
                ,f.TotalAPagarOriginal
                ,f.TotalAPagarFinal
                ,f.FechaLimitePagar
                ,ROW_NUMBER() OVER
                (
                    PARTITION BY f.PropiedadId
                    ORDER BY f.FechaFactura, f.Id
                ) AS FacturaNum
            FROM dbo.Factura f
            WHERE f.EstadoFacturaId = 1
        )
        INSERT INTO @PagosConFactura
        (
             NumeroFinca
            ,TipoMedioPagoId
            ,NumeroReferencia
            ,FacturaId
            ,TotalOriginal
            ,TotalFinal
            ,FechaLimite
        )
        SELECT
             po.NumeroFinca
            ,po.TipoMedioPagoId
            ,po.NumeroReferencia
            ,fp.Id
            ,fp.TotalAPagarOriginal
            ,fp.TotalAPagarFinal
            ,fp.FechaLimitePagar
        FROM PagosOrdenados po
        INNER JOIN FacturasPendientes fp
            ON fp.NumeroFinca = po.NumeroFinca
           AND fp.FacturaNum  = po.PagoNum;

        -- 3) Calcular morosidad e intereses
        DECLARE @IdCC_InteresesMoratorios INT;

        SELECT 
            @IdCC_InteresesMoratorios = cc.Id
        FROM dbo.ConceptoCobro cc
        WHERE cc.Nombre = 'InteresesMoratorios';

        UPDATE @PagosConFactura
        SET DiasMorosos =
            CASE 
                WHEN @inFecha > FechaLimite
                    THEN DATEDIFF(DAY, FechaLimite, @inFecha)
                ELSE 0
            END;

        UPDATE @PagosConFactura
        SET Interes =
            CASE 
                WHEN DiasMorosos > 0
                    THEN TotalOriginal * 0.04 / 30.0 * DiasMorosos
                ELSE 0
            END;

 
        -- 4) Insertar detalle de intereses
        INSERT INTO dbo.DetalleFactura
        (
             FacturaId
            ,ConceptoCobroId
            ,Monto
            ,Descripcion
        )
        SELECT
             FacturaId
            ,@IdCC_InteresesMoratorios
            ,Interes
            ,'Intereses moratorios'
        FROM @PagosConFactura
        WHERE Interes > 0;


        -- 5) Actualizar total final de factura
        UPDATE f
        SET f.TotalAPagarFinal = f.TotalAPagarFinal + p.Interes
        FROM dbo.Factura f
        INNER JOIN @PagosConFactura p 
            ON p.FacturaId = f.Id
        WHERE p.Interes > 0;


        -- 6) Insertar pagos
        INSERT INTO dbo.Pago
        (
             FacturaId
            ,TipoMedioPagoId
            ,FechaPago
            ,MontoPagado
            ,NumeroReferencia
        )
        SELECT
             FacturaId
            ,TipoMedioPagoId
            ,@inFecha
            ,(TotalFinal + Interes)
            ,NumeroReferencia
        FROM @PagosConFactura;


        -- 7) Marcar facturas pagadas
        UPDATE f
        SET f.EstadoFacturaId = 2
        FROM dbo.Factura f
        INNER JOIN @PagosConFactura p
            ON p.FacturaId = f.Id;


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
                ROLLBACK TRANSACTION SP_ProcesarPagosDelDia;
        END

        SET @outResultCode = 50030;

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
             'SP_ProcesarPagosDelDia'
            ,ERROR_NUMBER()
            ,ERROR_STATE()
            ,ERROR_SEVERITY()
            ,ERROR_LINE()
            ,'SP_ProcesarPagosDelDia'
            ,ERROR_MESSAGE()
            ,SYSDATETIME()
        );

        THROW;

    END CATCH
END
GO

