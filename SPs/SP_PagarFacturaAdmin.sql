USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_PagarFacturaAdmin]    Script Date: 23/11/2025 17:11:45 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_PagarFacturaAdmin]
(
    @inNumeroFinca       VARCHAR(64),
    @inTipoMedioPagoId   INT,
    @inNumeroReferencia  VARCHAR(128),
    @inFechaPago         DATE = NULL,          -- si no viene, usamos hoy
    @outResultCode       INT OUTPUT            -- 0 OK, otro error
)
AS

/*
SP para que el admin pague la factura más vieja (todo de una) y calcula impuesto si esta vencida
*/
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartedTran BIT = 0;

    BEGIN TRY
        IF @inFechaPago IS NULL
            SET @inFechaPago = CONVERT(DATE, SYSDATETIME());

        ------------------------------------------------------------
        -- Manejo estándar de transacciones anidadas
        ------------------------------------------------------------
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRAN;
            SET @StartedTran = 1;
        END
        ELSE
        BEGIN
            SAVE TRAN SP_PagarFacturaAdmin;
        END

        ------------------------------------------------------------
        -- 1) Buscar factura pendiente más vieja de esa finca
        ------------------------------------------------------------
        DECLARE 
            @FacturaId        INT,
            @TotalOriginal    MONEY,
            @TotalFinal       MONEY,
            @FechaLimite      DATE;

        SELECT TOP (1)
            @FacturaId     = f.Id,
            @TotalOriginal = f.TotalAPagarOriginal,
            @TotalFinal    = f.TotalAPagarFinal,
            @FechaLimite   = f.FechaLimitePagar
        FROM dbo.Factura f
        WHERE f.PropiedadId = @inNumeroFinca
          AND f.EstadoFacturaId = 1     -- Pendiente
        ORDER BY f.FechaFactura, f.Id;  -- más vieja primero

        IF @FacturaId IS NULL
        BEGIN
            -- No hay facturas pendientes para pagar
            SET @outResultCode = 40001;
            IF @StartedTran = 1 COMMIT;
            RETURN;
        END

        ------------------------------------------------------------
        -- 2) Si está vencida: calcular intereses moratorios
        ------------------------------------------------------------
        DECLARE 
            @DiasMora INT = 0,
            @Interes  MONEY = 0,
            @IdCC_InteresesMoratorios INT;

        SELECT @IdCC_InteresesMoratorios = Id
        FROM dbo.ConceptoCobro
        WHERE Nombre = 'InteresesMoratorios';

        IF (@inFechaPago > @FechaLimite)
        BEGIN
            SET @DiasMora = DATEDIFF(DAY, @FechaLimite, @inFechaPago);

            -- 4% mensual prorrateado diario (0.04/30 * días mora)
            SET @Interes = @TotalOriginal * 0.04 / 30.0 * @DiasMora;

            IF @Interes > 0
            BEGIN
                -- Insertar detalle de intereses
                INSERT INTO dbo.DetalleFactura
                (
                    FacturaId,
                    ConceptoCobroId,
                    Monto,
                    Descripcion
                )
                VALUES
                (
                    @FacturaId,
                    @IdCC_InteresesMoratorios,
                    @Interes,
                    'Intereses moratorios'
                );

                -- Actualizar TotalAPagarFinal
                UPDATE dbo.Factura
                SET TotalAPagarFinal = TotalAPagarFinal + @Interes
                WHERE Id = @FacturaId;

                -- refrescar total final para el pago
                SELECT @TotalFinal = TotalAPagarFinal
                FROM dbo.Factura
                WHERE Id = @FacturaId;
            END
        END

        ------------------------------------------------------------
        -- 3) Insertar Pago (pago total de esa factura)
        ------------------------------------------------------------
        INSERT INTO dbo.Pago
        (
            FacturaId,
            TipoMedioPagoId,
            FechaPago,
            MontoPagado,
            NumeroReferencia
        )
        VALUES
        (
            @FacturaId,
            @inTipoMedioPagoId,
            @inFechaPago,
            @TotalFinal,          -- incluye interés si aplicó
            @inNumeroReferencia
        );

        ------------------------------------------------------------
        -- 4) Marcar factura como pagada
        ------------------------------------------------------------
        UPDATE dbo.Factura
        SET EstadoFacturaId = 2   -- Pagada
        WHERE Id = @FacturaId;

        ------------------------------------------------------------
        -- 5) Fin OK (la reconexión NO se hace aquí)
        ------------------------------------------------------------
        IF @StartedTran = 1 COMMIT;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTran = 1
                ROLLBACK;
            ELSE
                ROLLBACK TRAN SP_PagarFacturaAdmin;
        END

        SET @outResultCode = 50050;

        INSERT INTO dbo.DBError
        (
            UserName,
            Number,
            State,
            Severity,
            Line,
            [Procedure],
            Message,
            DateTime
        )
        VALUES
        (
            'SP_PagarFacturaAdmin',
            ERROR_NUMBER(),
            ERROR_STATE(),
            ERROR_SEVERITY(),
            ERROR_LINE(),
            'SP_PagarFacturaAdmin',
            ERROR_MESSAGE(),
            SYSDATETIME()
        );
    END CATCH
END;
GO

