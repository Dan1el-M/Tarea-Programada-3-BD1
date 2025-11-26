USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_PagarFacturaAdmin]    Script Date: 26/11/2025 15:54:16 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_PagarFacturaAdmin]
(
      @inNumeroFinca      VARCHAR(64)
    , @inTipoMedioPagoId  INT
    , @inNumeroReferencia VARCHAR(128)
    , @inFechaPago        DATE = NULL
    , @outResultCode      INT  OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        IF ( @inFechaPago IS NULL )
            SET @inFechaPago = CONVERT(DATE, SYSDATETIME());

        DECLARE 
              @FacturaId              INT
            , @TotalOriginal          MONEY
            , @FechaLimite           DATE;

        SELECT TOP (1)
              @FacturaId     = f.Id
            , @TotalOriginal = f.TotalAPagarOriginal
            , @FechaLimite   = f.FechaLimitePagar
        FROM dbo.Factura AS f
        WHERE     f.PropiedadId     = @inNumeroFinca
              AND f.EstadoFacturaId = 1
        ORDER BY
              f.FechaFactura
            , f.Id;

        IF ( @FacturaId IS NULL )
        BEGIN
            SET @outResultCode = 50014; -- no hay factura pendiente
            RETURN;
        END;

        DECLARE 
              @Uso           VARCHAR(50)
            , @DebeTenerAgua BIT = 0;

        SELECT 
            @Uso = tu.Nombre
        FROM dbo.Propiedad AS pr
        INNER JOIN dbo.TipoUsoPropiedad AS tu
            ON tu.Id = pr.TipoUsoId
        WHERE pr.NumeroFinca = @inNumeroFinca;

        IF (    @Uso IN ('Residencial','Industrial','Comercial')
            AND EXISTS
                (
                    SELECT 1
                    FROM dbo.ConceptoCobroPropiedad AS cp
                    INNER JOIN dbo.ConceptoCobro AS cc
                        ON cc.Id = cp.ConceptoCobroId
                    INNER JOIN dbo.CC_ConsumoAgua AS ca
                        ON ca.Id = cc.Id
                    WHERE     cp.PropiedadId      = @inNumeroFinca
                          AND cp.TipoAsociacionId = 1
                )
           )
        BEGIN
            SET @DebeTenerAgua = 1;
        END;

        DECLARE 
              @DiasMora                INT   = 0
            , @Interes                 MONEY = 0
            , @IdCC_InteresesMoratorios INT
            , @TotalFinal              MONEY;

        SET @TotalFinal = @TotalOriginal;

        SELECT @IdCC_InteresesMoratorios = cc.Id
        FROM dbo.ConceptoCobro AS cc
        WHERE cc.Nombre = 'InteresesMoratorios';

        IF ( @inFechaPago > @FechaLimite )
        BEGIN
            SET @DiasMora = DATEDIFF(DAY, @FechaLimite, @inFechaPago);
            SET @Interes  = @TotalOriginal * 0.04 / 30.0 * @DiasMora;
            SET @TotalFinal = @TotalFinal + ISNULL(@Interes, 0);
        END;

        DECLARE 
              @IdCC_Reconexion   INT
            , @MontoReconexion   MONEY = 0
            , @TieneCortaActiva  BIT   = 0
            , @EsUltimaVencida   BIT   = 0;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.OrdenCorta AS oc
            WHERE     oc.PropiedadId = @inNumeroFinca
                  AND oc.Estado      = 1
        )
            SET @TieneCortaActiva = 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Factura AS f2
            WHERE     f2.PropiedadId     = @inNumeroFinca
                  AND f2.EstadoFacturaId = 1
                  AND f2.FechaLimitePagar < @inFechaPago
                  AND f2.Id <> @FacturaId
        )
            SET @EsUltimaVencida = 1;

        IF (    @DebeTenerAgua    = 1
            AND @TieneCortaActiva = 1
            AND @EsUltimaVencida  = 1
           )
        BEGIN
            SELECT
                  @IdCC_Reconexion = cc.Id
                , @MontoReconexion = r.ValorFijo
            FROM dbo.CC_ReconexionAgua AS r
            INNER JOIN dbo.ConceptoCobro AS cc
                ON cc.Id = r.Id;

            SET @TotalFinal = @TotalFinal + ISNULL(@MontoReconexion, 0);
        END;

        BEGIN TRANSACTION;

        IF ( @Interes > 0 )
        BEGIN
            INSERT INTO dbo.DetalleFactura
            (
                  FacturaId
                , ConceptoCobroId
                , Monto
                , Descripcion
            )
            VALUES
            (
                  @FacturaId
                , @IdCC_InteresesMoratorios
                , @Interes
                , 'Intereses moratorios'
            );
        END;

        IF (    @IdCC_Reconexion IS NOT NULL
            AND @MontoReconexion IS NOT NULL
            AND @MontoReconexion > 0
            AND @DebeTenerAgua    = 1
            AND @TieneCortaActiva = 1
            AND @EsUltimaVencida  = 1
           )
        BEGIN
            INSERT INTO dbo.DetalleFactura
            (
                  FacturaId
                , ConceptoCobroId
                , Monto
                , Descripcion
            )
            VALUES
            (
                  @FacturaId
                , @IdCC_Reconexion
                , @MontoReconexion
                , 'Reconexión de agua'
            );

            UPDATE oc
            SET
                  oc.Estado        = 2
                , oc.FechaEjecutada = @inFechaPago
            FROM dbo.OrdenCorta AS oc
            WHERE     oc.PropiedadId = @inNumeroFinca
                  AND oc.Estado      = 1;
        END;

        UPDATE dbo.Factura
        SET TotalAPagarFinal = @TotalFinal
        WHERE Id = @FacturaId;

        INSERT INTO dbo.Pago
        (
              FacturaId
            , TipoMedioPagoId
            , FechaPago
            , MontoPagado
            , NumeroReferencia
        )
        VALUES
        (
              @FacturaId
            , @inTipoMedioPagoId
            , @inFechaPago
            , @TotalFinal
            , @inNumeroReferencia
        );

        UPDATE dbo.Factura
        SET EstadoFacturaId = 2
        WHERE Id = @FacturaId;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;

        SELECT 
              f.Id                AS FacturaId
            , f.PropiedadId
            , f.FechaFactura
            , f.FechaLimitePagar
            , f.TotalAPagarOriginal
            , f.TotalAPagarFinal
            , f.EstadoFacturaId
        FROM dbo.Factura AS f
        WHERE f.Id = @FacturaId;

        SELECT 
              df.ConceptoCobroId
            , cc.Nombre       AS NombreCC
            , df.Monto
            , df.Descripcion
        FROM dbo.DetalleFactura AS df
        INNER JOIN dbo.ConceptoCobro AS cc
            ON cc.Id = df.ConceptoCobroId
        WHERE df.FacturaId = @FacturaId
        ORDER BY
            df.Id;

        RETURN;
    END TRY

    BEGIN CATCH

        IF ( @@TRANCOUNT > 0 )
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50011;

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

