USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_GenerarCortasDelDia]    Script Date: 26/11/2025 15:51:47 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_GenerarCortasDelDia]
(
      @inFecha       DATE
    , @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY


        -- 1) DiasGraciaCorta desde ParametrosSistema
        DECLARE @DiasGracia INT =
        (
            SELECT TRY_CONVERT(INT, ps.Valor)
            FROM dbo.ParametrosSistema AS ps
            WHERE ps.Nombre = 'DiasGraciaCorta'
        );

        IF ( @DiasGracia IS NULL )
            SET @DiasGracia = 10;  

        -- 2) facturas candidatas a corta
        DECLARE @FacturasCandidatas TABLE
        (
              FacturaId        INT
            , PropiedadId      VARCHAR(64)
            , FechaFactura     DATE
            , FechaLimitePagar DATE
            , rn               INT
        );

        ;WITH Base AS
        (
            SELECT DISTINCT
                  f.Id               AS FacturaId
                , f.PropiedadId      AS PropiedadId
                , f.FechaFactura
                , f.FechaLimitePagar
            FROM dbo.Factura AS f
            INNER JOIN dbo.Propiedad AS pr
                ON pr.NumeroFinca = f.PropiedadId
            INNER JOIN dbo.TipoUsoPropiedad AS tu
                ON tu.Id = pr.TipoUsoId
            INNER JOIN dbo.ConceptoCobroPropiedad AS cp
                ON     cp.PropiedadId      = pr.NumeroFinca
                   AND cp.TipoAsociacionId = 1      -- CC activo
            INNER JOIN dbo.CC_ConsumoAgua AS ca
                ON ca.Id = cp.ConceptoCobroId       -- CC de agua
            WHERE     f.EstadoFacturaId = 1         -- pendiente
                  AND DATEADD(DAY, @DiasGracia, f.FechaLimitePagar) < @inFecha
                  AND tu.Nombre IN ('Residencial','Industrial','Comercial')
        )
        INSERT INTO @FacturasCandidatas
        (
              FacturaId
            , PropiedadId
            , FechaFactura
            , FechaLimitePagar
            , rn
        )
        SELECT
              b.FacturaId
            , b.PropiedadId
            , b.FechaFactura
            , b.FechaLimitePagar
            , ROW_NUMBER() OVER
              (
                  PARTITION BY b.PropiedadId
                  ORDER BY     b.FechaFactura
                             , b.FacturaId
              ) AS rn
        FROM Base AS b;


        -- 3) insertar órdenes de corta
        BEGIN TRANSACTION;

        INSERT INTO dbo.OrdenCorta
        (
              PropiedadId
            , FacturaId
            , FechaGenerada
            , FechaEjecutada
            , Estado
        )
        SELECT
              fc.PropiedadId
            , fc.FacturaId
            , @inFecha
            , NULL
            , 1           
        FROM @FacturasCandidatas AS fc
        WHERE     fc.rn = 1
              AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.OrdenCorta AS oc
                      WHERE     oc.PropiedadId = fc.PropiedadId
                            AND oc.Estado      = 1   
                  );

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH
        IF ( @@TRANCOUNT > 0 )
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50005;

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

