USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarCatalogosDesdeXML]    Script Date: 26/11/2025 15:50:27 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarCatalogosDesdeXML]
(
      @inXmlData     XML          -- XML con el contenido de catalogosV2.xml
    , @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        ------------------------------------------------------------
        -- 0) PRE-PROCESO: parámetros y tabla @CCs desde el XML
        ------------------------------------------------------------
        DECLARE
              @DiasVencimientoFactura INT
            , @DiasGraciaCorta        INT;

        SELECT
              @DiasVencimientoFactura = @inXmlData.value(
                                        '(/Catalogos/ParametrosSistema/DiasVencimientoFactura/text())[1]', 'int')
            , @DiasGraciaCorta        = @inXmlData.value(
                                        '(/Catalogos/ParametrosSistema/DiasGraciaCorta/text())[1]', 'int');

        DECLARE @CCs TABLE
        (
              Id                   INT
            , Nombre               NVARCHAR(128)
            , TipoMontoCCId        INT
            , PeriodoMontoCCId     INT
            , ValorMinimo          MONEY
            , ValorMinimoM3        INT
            , ValorFijoM3Adicional MONEY
            , ValorPorcentual      DECIMAL(10,2)
            , ValorFijo            MONEY
            , ValorM2Minimo        INT
            , ValorTramosM2        INT
        );

        INSERT INTO @CCs
        (
              Id
            , Nombre
            , TipoMontoCCId
            , PeriodoMontoCCId
            , ValorMinimo
            , ValorMinimoM3
            , ValorFijoM3Adicional
            , ValorPorcentual
            , ValorFijo
            , ValorM2Minimo
            , ValorTramosM2
        )
        SELECT
              C.value('@id','int')
            , C.value('@nombre','nvarchar(128)')
            , C.value('@TipoMontoCC','int')
            , C.value('@PeriodoMontoCC','int')
            , NULLIF(C.value('@ValorMinimo',           'money'),        0)
            , NULLIF(C.value('@ValorMinimoM3',         'int'),          0)
            , NULLIF(C.value('@ValorFijoM3Adicional',  'money'),        0)
            , NULLIF(
                        TRY_CONVERT(DECIMAL(10,2), C.value('@ValorPorcentual','nvarchar(50)'))
                    ,   0
                    )
            , NULLIF(C.value('@ValorFijo',             'money'),        0)
            , NULLIF(C.value('@ValorM2Minimo',         'int'),          0)
            , NULLIF(C.value('@ValorTramosM2',         'int'),          0)
        FROM @inXmlData.nodes('/Catalogos/CCs/CC') AS T(C);

        ------------------------------------------------------------
        -- 1) TRANSACCIÓN: inserción de catálogos
        ------------------------------------------------------------
        BEGIN TRANSACTION;

        -- PARÁMETROS DEL SISTEMA
        INSERT INTO dbo.ParametrosSistema
        (Nombre, Valor)
        VALUES
              ( 'DiasVencimientoFactura'
              , CONVERT(NVARCHAR(256), @DiasVencimientoFactura)
              )
            , ( 'DiasGraciaCorta'
              , CONVERT(NVARCHAR(256), @DiasGraciaCorta)
              );

        -- TIPO MOVIMIENTO LECTURA MEDIDOR
        INSERT INTO dbo.TipoMovimientoLecturaMedidor(Id, Nombre)
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMovimientoLecturaMedidor/TipoMov') AS T(X);

        -- TIPO USO PROPIEDAD
        INSERT INTO dbo.TipoUsoPropiedad(Id, Nombre)
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoUsoPropiedad/TipoUso') AS T(X);

        -- TIPO ZONA PROPIEDAD
        INSERT INTO dbo.TipoZonaPropiedad(Id, Nombre)
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoZonaPropiedad/TipoZona') AS T(X);

        -- USUARIO ADMINISTRADOR DESDE XML
        INSERT INTO dbo.Usuario
        (
              Id
            , NombreUsuario
            , Contrasena
        )
        SELECT
              A.value('@id','int')
            , A.value('@nombre',   'VARCHAR(64)')
            , A.value('@password', 'VARCHAR(128)')
        FROM @inXmlData.nodes('/Catalogos/UsuarioAdmin/Admin') AS T(A);

        -- TIPO MEDIO PAGO
        INSERT INTO dbo.TipoMedioPago (Id, Nombre)
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMedioPago/MedioPago') AS T(X);

        -- PERIODO MONTO CC
        INSERT INTO dbo.PeriodoMontoCC
        (
              Id
            , Nombre
            , Dias
            , QMeses
        )
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
            , NULLIF(X.value('@dias','int'),    0)
            , NULLIF(X.value('@qMeses','int'),  0)
        FROM @inXmlData.nodes('/Catalogos/PeriodoMontoCC/PeriodoMonto') AS T(X);

        -- TIPO MONTO CC
        INSERT INTO dbo.TipoMontoCC
        ( Id, Nombre)
        SELECT
              X.value('@id','int')
            , X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMontoCC/TipoMonto') AS T(X);

       
        -- 2) CONCEPTOS DE COBRO (HERENCIA)
        -- PADRE
        INSERT INTO dbo.ConceptoCobro
        (
              Id
            , Nombre
            , TipoMontoCCId
            , PeriodoMontoCCId
        )
        SELECT
              C.Id
            , C.Nombre
            , C.TipoMontoCCId
            , C.PeriodoMontoCCId
        FROM @CCs AS C;

        -- Consumo de agua
        INSERT INTO dbo.CC_ConsumoAgua
        (
              Id
            , ValorMinimo
            , ValorMinimoM3
            , ValorFijoM3Adicional
        )
        SELECT
              C.Id
            , C.ValorMinimo
            , C.ValorMinimoM3
            , C.ValorFijoM3Adicional
        FROM @CCs AS C
        WHERE ( C.Nombre = 'ConsumoAgua' );

        -- Patente comercial
        INSERT INTO dbo.CC_PatenteComercial(Id, ValorFijo)
        SELECT C.Id, C.ValorFijo
        FROM @CCs AS C
        WHERE ( C.Nombre = 'PatenteComercial' );

        -- Impuesto a la propiedad
        INSERT INTO dbo.CC_ImpuestoPropiedad
        (
              Id
            , ValorPorcentual
            , ValorM2Minimo
            , ValorTramosM2
        )
        SELECT
              C.Id
            , C.ValorPorcentual
            , C.ValorM2Minimo
            , C.ValorTramosM2
        FROM @CCs AS C
        WHERE ( C.Nombre = 'ImpuestoPropiedad' );

        -- Recolección basura
        INSERT INTO dbo.CC_RecoleccionBasura
        (
              Id
            , ValorMinimo
            , ValorFijo
            , ValorM2Minimo
        )
        SELECT
              C.Id
            , C.ValorMinimo
            , C.ValorFijo
            , C.ValorM2Minimo
        FROM @CCs AS C
        WHERE ( C.Nombre = 'RecoleccionBasura' );

        -- Mantenimiento parques
        INSERT INTO dbo.CC_MantenimientoParques(Id, ValorFijo)
        SELECT C.Id, C.ValorFijo
        FROM @CCs AS C
        WHERE ( C.Nombre = 'MantenimientoParques' );

        -- Reconexión agua
        INSERT INTO dbo.CC_ReconexionAgua(Id, ValorFijo)
        SELECT C.Id, C.ValorFijo
        FROM @CCs AS C
        WHERE ( C.Nombre = 'ReconexionAgua' );

        -- Intereses moratorios
        INSERT INTO dbo.CC_InteresesMoratorios(Id, ValorPorcentual)
        SELECT C.Id, C.ValorPorcentual
        FROM @CCs AS C
        WHERE ( C.Nombre = 'InteresesMoratorios' );

        ------------------------------------------------------------
        -- FIN TRANSACCIÓN
        ------------------------------------------------------------
        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50001;

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
    END CATCH;
END;
GO

