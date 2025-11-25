USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarCatalogosDesdeXML]    Script Date: 24/11/2025 16:32:48 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarCatalogosDesdeXML]
    @inXmlData     XML,          -- XML con el contenido de catalogosV2.xml
    @outResultCode INT OUTPUT    
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        --  PARÁMETROS DEL SISTEMA
        INSERT INTO dbo.ParametrosSistema (
                                        Nombre
                                        , Valor
                                          )
        VALUES 
            (
            'DiasVencimientoFactura'
            , CONVERT(NVARCHAR(256)
            , @inXmlData.value('(/Catalogos/ParametrosSistema/DiasVencimientoFactura/text())[1]','int' )))
            , ('DiasGraciaCorta'
            , CONVERT(NVARCHAR(256)
            , @inXmlData.value('(/Catalogos/ParametrosSistema/DiasGraciaCorta/text())[1]','int'))
            );


        --TIPO MOVIMIENTO LECTURA MEDIDOR
        INSERT INTO dbo.TipoMovimientoLecturaMedidor (
                                                        Id
                                                        , Nombre
                                                      )
        SELECT
            T.X.value('@id','int')
                      ,T.X.value('@nombre','nvarchar(128)')

        FROM @inXmlData.nodes('/Catalogos/TipoMovimientoLecturaMedidor/TipoMov') AS T(X);

        -- TIPO USO PROPIEDAD
        INSERT INTO dbo.TipoUsoPropiedad (Id, Nombre)
        SELECT
             T.X.value('@id','int')
            ,T.X.value('@nombre','nvarchar(128)')

        FROM @inXmlData.nodes('/Catalogos/TipoUsoPropiedad/TipoUso') AS T(X);


        -- TIPO ZONA PROPIEDAD
        INSERT INTO dbo.TipoZonaPropiedad (Id, Nombre)
        SELECT
             T.X.value('@id','int')
            ,T.X.value('@nombre','nvarchar(128)')

        FROM @inXmlData.nodes('/Catalogos/TipoZonaPropiedad/TipoZona') AS T(X);


        -- USUARIO ADMINISTRADOR DESDE XML
        INSERT INTO dbo.Usuario (
                                    Id
                                  , NombreUsuario
                                  , Contrasena
                                 )
        SELECT
             T.A.value('@id','int')
            ,T.A.value('@nombre',   'varchar(64)')
            ,T.A.value('@password', 'varchar(128)')

        FROM @inXmlData.nodes('/Catalogos/UsuarioAdmin/Admin') AS T(A);

  
        -- TIPO MEDIO PAGO
        INSERT INTO dbo.TipoMedioPago (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMedioPago/MedioPago') AS T(X);


        -- PERIODO MONTO CC
        INSERT INTO dbo.PeriodoMontoCC (Id, Nombre, Dias, QMeses)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)'),
            NULLIF(T.X.value('@dias','int'),   0),
            NULLIF(T.X.value('@qMeses','int'), 0)
        FROM @inXmlData.nodes('/Catalogos/PeriodoMontoCC/PeriodoMonto') AS T(X);

        -- TIPO MONTO CC
        INSERT INTO dbo.TipoMontoCC (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMontoCC/TipoMonto') AS T(X);

        
         -- CONCEPTOS DE COBRO (HERENCIA)


        DECLARE @CCs TABLE(
             Id                   INT
            ,Nombre               NVARCHAR(128)
            ,TipoMontoCCId        INT
            ,PeriodoMontoCCId     INT
            ,ValorMinimo          MONEY
            ,ValorMinimoM3        INT
            ,ValorFijoM3Adicional MONEY
            ,ValorPorcentual      DECIMAL(10,2)
            ,ValorFijo            MONEY
            ,ValorM2Minimo        INT
            ,ValorTramosM2        INT
        );

        INSERT INTO @CCs
        SELECT
            C.value('@id','int')
            ,C.value('@nombre','nvarchar(128)')
            ,C.value('@TipoMontoCC','int')
            ,C.value('@PeriodoMontoCC','int')
            ,NULLIF(C.value('@ValorMinimo', 'money'), 0)
            ,NULLIF(C.value('@ValorMinimoM3', 'int'), 0)
            ,NULLIF(C.value('@ValorFijoM3Adicional', 'money'), 0)
            ,NULLIF(TRY_CONVERT(decimal(10,2), C.value('@ValorPorcentual','nvarchar(50)')), 0)
            ,NULLIF(C.value('@ValorFijo', 'money'), 0)
            ,NULLIF(C.value('@ValorM2Minimo', 'int'), 0)
            ,NULLIF(C.value('@ValorTramosM2', 'int'), 0)

        FROM @inXmlData.nodes('/Catalogos/CCs/CC') AS T(C);

        -- 1) PADRE: siempre se inserta acá
        INSERT INTO dbo.ConceptoCobro (
                                         Id
                                       , Nombre
                                       , TipoMontoCCId
                                       , PeriodoMontoCCId
                                       )

        SELECT    Id
                , Nombre
                , TipoMontoCCId
                , PeriodoMontoCCId

        FROM @CCs;

        -- Consumo de Agua
        INSERT INTO dbo.CC_ConsumoAgua (
                                        Id
                                        , ValorMinimo
                                        , ValorMinimoM3
                                        , ValorFijoM3Adicional
                                        )

        SELECT      Id
                    , ValorMinimo
                    , ValorMinimoM3
                    , ValorFijoM3Adicional

        FROM @CCs
        WHERE Nombre = 'ConsumoAgua';

        -- Patente Comercial
        INSERT INTO dbo.CC_PatenteComercial (Id, ValorFijo )

        SELECT    Id
                , ValorFijo

        FROM @CCs
        WHERE Nombre = 'PatenteComercial';

        -- Impuesto a la Propiedad
        INSERT INTO dbo.CC_ImpuestoPropiedad (
                                                Id
                                                , ValorPorcentual
                                                , ValorM2Minimo
                                                , ValorTramosM2
                                              )
        SELECT    Id
                , ValorPorcentual
                , ValorM2Minimo
                , ValorTramosM2

        FROM @CCs
        WHERE Nombre = 'ImpuestoPropiedad';

        -- Recolección Basura
        INSERT INTO dbo.CC_RecoleccionBasura (
                                                Id
                                                , ValorMinimo
                                                , ValorFijo
                                                , ValorM2Minimo
                                                )

        SELECT    Id
                , ValorMinimo
                , ValorFijo
                , ValorM2Minimo

        FROM @CCs
        WHERE Nombre = 'RecoleccionBasura';

        -- Mantenimiento Parques
        INSERT INTO dbo.CC_MantenimientoParques (Id, ValorFijo)
        SELECT Id, ValorFijo
        FROM @CCs
        WHERE Nombre = 'MantenimientoParques';

        -- Reconexion Agua
        INSERT INTO dbo.CC_ReconexionAgua ( Id, ValorFijo)
        SELECT Id,ValorFijo
        FROM @CCs
        WHERE Nombre = 'ReconexionAgua';

        -- Intereses Moratorios
        INSERT INTO dbo.CC_InteresesMoratorios (Id, ValorPorcentual)
        SELECT Id,ValorPorcentual
        FROM @CCs
        WHERE Nombre = 'InteresesMoratorios';


        COMMIT TRANSACTION;
        SET @outResultCode = 0;
        RETURN;

    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SET @outResultCode = 50001;

        INSERT INTO dbo.DBError (
            UserName
            , Number
            , State
            , Severity
            , Line
            , [Procedure]
            , Message
            , DateTime
        )
        VALUES (
            'SP_CargarCatalogosDesdeXML'
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_CargarCatalogosDesdeXML'
            , ERROR_MESSAGE()
            , GETDATE()
        );
    END CATCH;
END;
GO

