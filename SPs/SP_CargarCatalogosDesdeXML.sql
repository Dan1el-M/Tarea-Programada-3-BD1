USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_CargarCatalogosDesdeXML]    Script Date: 19/11/2025 21:34:04 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_CargarCatalogosDesdeXML]
    @inXmlData     XML,          -- XML con el contenido de catalogosV2.xml
    @outResultCode INT OUTPUT    -- Código de resultado (0 = OK, otro = error)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        ---------------------------------------------------------------------
        -- 1. PARÁMETROS DEL SISTEMA
        --   <ParametrosSistema>
        --     <DiasVencimientoFactura>15</DiasVencimientoFactura>
        --     <DiasGraciaCorta>10</DiasGraciaCorta>
        --   </ParametrosSistema>
        ---------------------------------------------------------------------
        INSERT INTO dbo.ParametrosSistema (Nombre, Valor)
        VALUES 
            ('DiasVencimientoFactura',
             CONVERT(NVARCHAR(256), @inXmlData.value(
                '(/Catalogos/ParametrosSistema/DiasVencimientoFactura/text())[1]',
                'int'
             ))),
            ('DiasGraciaCorta',
             CONVERT(NVARCHAR(256), @inXmlData.value(
                '(/Catalogos/ParametrosSistema/DiasGraciaCorta/text())[1]',
                'int'
             )));

        ---------------------------------------------------------------------
        -- 2. TIPO MOVIMIENTO LECTURA MEDIDOR
        --   <TipoMovimientoLecturaMedidor>
        --     <TipoMov id="1" nombre="Lectura"/>
        --   </TipoMovimientoLecturaMedidor>
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoMovimientoLecturaMedidor (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMovimientoLecturaMedidor/TipoMov') AS T(X);

        ---------------------------------------------------------------------
        -- 3. TIPO USO PROPIEDAD
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoUsoPropiedad (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoUsoPropiedad/TipoUso') AS T(X);

        ---------------------------------------------------------------------
        -- 4. TIPO ZONA PROPIEDAD
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoZonaPropiedad (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoZonaPropiedad/TipoZona') AS T(X);

        ---------------------------------------------------------------------
        -- 5. USUARIO ADMINISTRADOR DESDE XML
        --   <UsuarioAdmin>
        --     <Admin id="1" nombre="Administrador" password="SoyAdmin"/>
        --   </UsuarioAdmin>
        ---------------------------------------------------------------------
        INSERT INTO dbo.Usuario (NombreUsuario, Contrasena)
        SELECT
            T.A.value('@nombre',   'varchar(64)'),
            T.A.value('@password', 'varchar(128)')
        FROM @inXmlData.nodes('/Catalogos/UsuarioAdmin/Admin') AS T(A);

        ---------------------------------------------------------------------
        -- 6. TIPO ASOCIACION
        --   <TipoAsociacion>
        --     <TipoAso id="1" nombre="Asociar"/>
        --   </TipoAsociacion>
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoAsociacion (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoAsociacion/TipoAso') AS T(X);

        ---------------------------------------------------------------------
        -- 8. TIPO MEDIO PAGO
        --   <TipoMedioPago>
        --     <MedioPago id="1" nombre="Efectivo"/>
        --   </TipoMedioPago>
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoMedioPago (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMedioPago/MedioPago') AS T(X);

        ---------------------------------------------------------------------
        -- 9. PERIODO MONTO CC
        --   <PeriodoMontoCC>
        --     <PeriodoMonto id="1" nombre="Mensual" qMeses="1" .../>
        --   </PeriodoMontoCC>
        ---------------------------------------------------------------------
        INSERT INTO dbo.PeriodoMontoCC (Id, Nombre, Dias, QMeses)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)'),
            NULLIF(T.X.value('@dias','int'),   0),
            NULLIF(T.X.value('@qMeses','int'), 0)
        FROM @inXmlData.nodes('/Catalogos/PeriodoMontoCC/PeriodoMonto') AS T(X);

        ---------------------------------------------------------------------
        -- 10. TIPO MONTO CC
        ---------------------------------------------------------------------
        INSERT INTO dbo.TipoMontoCC (Id, Nombre)
        SELECT
            T.X.value('@id','int'),
            T.X.value('@nombre','nvarchar(128)')
        FROM @inXmlData.nodes('/Catalogos/TipoMontoCC/TipoMonto') AS T(X);

        ---------------------------------------------------------------------
        -- 11. CONCEPTOS DE COBRO (CCs)
        --   <CCs>
        --     <CC id="1" nombre="ConsumoAgua" TipoMontoCC="2" PeriodoMontoCC="1"
        --         ValorMinimo="0" ValorMinimoM3="" ValorFijoM3Adicional=""
        --         ValorPorcentual="" ValorFijo="" ValorM2Minimo="" ValorTramosM2=""/>
        --   </CCs>
        ---------------------------------------------------------------------
        INSERT INTO dbo.ConceptoCobro (
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
        , ValorTractosM2
    )
    SELECT
        C.value('@id','int'),
        C.value('@nombre','nvarchar(128)'),
        C.value('@TipoMontoCC','int'),
        C.value('@PeriodoMontoCC','int'),
        NULLIF(C.value('@ValorMinimo', 'money'), 0),
        NULLIF(C.value('@ValorMinimoM3', 'int'), 0),
        NULLIF(C.value('@ValorFijoM3Adicional', 'money'), 0),
        NULLIF(TRY_CONVERT(decimal(10,2), C.value('@ValorPorcentual','nvarchar(50)')), 0),
        NULLIF(C.value('@ValorFijo', 'money'), 0),
        NULLIF(C.value('@ValorM2Minimo', 'int'), 0),
        NULLIF(C.value('@ValorTramosM2', 'int'), 0)

    FROM @inXmlData.nodes('/Catalogos/CCs/CC') AS T(C);


        ---------------------------------------------------------------------
        -- ÉXITO
        ---------------------------------------------------------------------
        SET @outResultCode = 0;
        RETURN;
    END TRY
    BEGIN CATCH
        ---------------------------------------------------------------------
        -- ERROR: registramos en DBError y devolvemos código
        ---------------------------------------------------------------------
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

