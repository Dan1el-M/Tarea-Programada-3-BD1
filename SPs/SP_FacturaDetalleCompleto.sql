USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_FacturaDetalleCompleto]    Script Date: 26/11/2025 15:51:14 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_FacturaDetalleCompleto]
(
      @inNumeroFactura   INT
    , @inFechaReferencia DATE = NULL  -- si viene NULL se usa hoy
    , @outResultCode     INT  OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

    
        -- Fecha de referencia
        IF ( @inFechaReferencia IS NULL )
            SET @inFechaReferencia = CONVERT(DATE, SYSDATETIME());

        -- 1) Datos de la factura + propiedad
        DECLARE 
              @EstadoFacturaId   INT
            , @PropiedadId       VARCHAR(64)
            , @FechaFactura      DATE
            , @FechaLimitePagar  DATE
            , @TotalOriginal     MONEY
            , @TotalGuardado     MONEY
            , @FechaPago         DATE
            , @Uso               VARCHAR(50)
            , @Zona              VARCHAR(50)
            , @DebeTenerAgua     BIT = 0;

        SELECT
              @EstadoFacturaId   = f.EstadoFacturaId
            , @PropiedadId       = f.PropiedadId       -- NumeroFinca
            , @FechaFactura      = f.FechaFactura
            , @FechaLimitePagar  = f.FechaLimitePagar
            , @TotalOriginal     = f.TotalAPagarOriginal
            , @TotalGuardado     = f.TotalAPagarFinal
            , @Uso               = tu.Nombre
            , @Zona              = tz.Nombre
            , @FechaPago         = MAX(p.FechaPago)
        FROM dbo.Factura AS f
        LEFT JOIN dbo.Pago AS p
            ON p.FacturaId = f.Id
        LEFT JOIN dbo.Propiedad AS pr
            ON pr.NumeroFinca = f.PropiedadId
        LEFT JOIN dbo.TipoUsoPropiedad AS tu
            ON tu.Id = pr.TipoUsoId
        LEFT JOIN dbo.TipoZonaPropiedad AS tz
            ON tz.Id = pr.TipoZonaId
        WHERE f.Id = @inNumeroFactura
        GROUP BY
              f.EstadoFacturaId
            , f.PropiedadId
            , f.FechaFactura
            , f.FechaLimitePagar
            , f.TotalAPagarOriginal
            , f.TotalAPagarFinal
            , tu.Nombre
            , tz.Nombre;

        IF ( @EstadoFacturaId IS NULL )
        BEGIN
            -- Factura no existe
            SET @outResultCode = 40002;
            RETURN;
        END;


        --  Regla "debe tener agua"

        SET @DebeTenerAgua = 0;

        IF (    @Uso IN ('Residencial','Industrial','Comercial')
            AND EXISTS
                (
                    SELECT 1
                    FROM dbo.ConceptoCobroPropiedad AS cp
                    INNER JOIN dbo.ConceptoCobro AS cc
                        ON cc.Id = cp.ConceptoCobroId
                    INNER JOIN dbo.CC_ConsumoAgua AS ca
                        ON ca.Id = cc.Id   -- este CC es de tipo ConsumoAgua
                    WHERE     cp.PropiedadId      = @PropiedadId
                          AND cp.TipoAsociacionId = 1   -- SOLO los activos
                )
           )
        BEGIN
            SET @DebeTenerAgua = 1;
        END;


        -- 2) Cálculo dinámico de intereses / reconexión
        DECLARE 
              @FechaRef          DATE  = @inFechaReferencia
            , @DiasMora          INT   = 0
            , @Interes           MONEY = 0
            , @IdCC_Intereses    INT   = NULL
            , @TieneCortaActiva  BIT   = 0
            , @EsUltimaVencida   BIT   = 0
            , @IdCC_Reconexion   INT   = NULL
            , @MontoReconexion   MONEY = 0;

        IF ( @EstadoFacturaId = 1 )  -- 1 = Pendiente
        BEGIN

            -- Intereses moratorios
            SELECT @IdCC_Intereses = cc.Id
            FROM dbo.ConceptoCobro AS cc
            WHERE cc.Nombre = 'InteresesMoratorios';

            IF ( @FechaRef > @FechaLimitePagar AND @IdCC_Intereses IS NOT NULL )
            BEGIN
                SET @DiasMora = DATEDIFF(DAY, @FechaLimitePagar, @FechaRef);
                SET @Interes  = @TotalOriginal * 0.04 / 30.0 * @DiasMora;
            END;

   
            -- Reconexión de agua

            IF (    @DebeTenerAgua = 1
                AND @FechaLimitePagar < @FechaRef
                AND @EstadoFacturaId = 1
               )
            BEGIN
                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.OrdenCorta AS oc
                    WHERE     oc.PropiedadId = @PropiedadId
                          AND oc.Estado      = 1       -- corta activa
                )
                    SET @TieneCortaActiva = 1;

                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.Factura AS f2
                    WHERE     f2.PropiedadId     = @PropiedadId
                          AND f2.EstadoFacturaId = 1
                          AND f2.FechaLimitePagar < @FechaRef
                          AND f2.Id <> @inNumeroFactura
                )
                    SET @EsUltimaVencida = 1;

                IF ( @TieneCortaActiva = 1 AND @EsUltimaVencida = 1 )
                BEGIN
                    SELECT
                          @IdCC_Reconexion = cc.Id
                        , @MontoReconexion = r.ValorFijo
                    FROM dbo.CC_ReconexionAgua AS r
                    INNER JOIN dbo.ConceptoCobro AS cc
                        ON cc.Id = r.Id;

                    IF ( @MontoReconexion IS NULL )
                        SET @MontoReconexion = 0;
                END;
            END
            ELSE
            BEGIN

                SET @MontoReconexion = 0;
            END;
        END;


        -- 4) RESULTADOS
        SELECT
              NumeroFactura       = @inNumeroFactura
            , PropiedadId         = @PropiedadId
            , FechaFactura        = @FechaFactura
            , FechaLimitePagar    = @FechaLimitePagar
            , EstadoFacturaId     = @EstadoFacturaId
            , FechaPago           = @FechaPago
            , Uso                 = @Uso
            , Zona                = @Zona
            , FechaReferencia     = @FechaRef
            , TotalOriginal       = @TotalOriginal
            , InteresesMoratorios = @Interes
            , MontoReconexion     = @MontoReconexion
            , TotalCalculado      = CASE 
                                        WHEN @EstadoFacturaId = 1 
                                            THEN @TotalOriginal
                                                 + @Interes
                                                 + @MontoReconexion
                                        ELSE @TotalGuardado
                                    END
            , TotalGuardado       = @TotalGuardado;


        -- Detalle (BASE + EXTRAS)
        ;WITH DetalleBase AS
        (
            SELECT
                  df.ConceptoCobroId
                , cc.Nombre       AS NombreCC
                , df.Monto
                , df.Descripcion
            FROM dbo.DetalleFactura AS df
            INNER JOIN dbo.ConceptoCobro AS cc
                ON cc.Id = df.ConceptoCobroId
            WHERE df.FacturaId = @inNumeroFactura
        ),
        DetalleExtraPendiente AS
        (
            SELECT
                  @IdCC_Intereses        AS ConceptoCobroId
                , 'InteresesMoratorios'  AS NombreCC
                , @Interes               AS Monto
                , 'Intereses moratorios' AS Descripcion
            WHERE     @EstadoFacturaId = 1
                  AND @Interes > 0

            UNION ALL

            SELECT
                  @IdCC_Reconexion       AS ConceptoCobroId
                , 'ReconexionAgua'       AS NombreCC
                , @MontoReconexion       AS Monto
                , 'Reconexión de agua'   AS Descripcion
            WHERE     @EstadoFacturaId = 1
                  AND @MontoReconexion > 0
        )
        SELECT
              d.ConceptoCobroId
            , d.NombreCC
            , d.Monto
            , d.Descripcion
        FROM DetalleBase AS d
        UNION ALL
        SELECT
              e.ConceptoCobroId
            , e.NombreCC
            , e.Monto
            , e.Descripcion
        FROM DetalleExtraPendiente AS e
        ORDER BY
              NombreCC
            , ConceptoCobroId;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH
        SET @outResultCode = 50003;

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

