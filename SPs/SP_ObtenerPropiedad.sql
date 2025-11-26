USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ObtenerPropiedad]    Script Date: 26/11/2025 15:53:54 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_ObtenerPropiedad]
(
      @inNumeroFinca VARCHAR(64)
    , @outResultCode INT OUTPUT
)
/*
SP que obtiene los datos completos de una propiedad:
    - Información de la propiedad (finca, medidor, área, valor fiscal)
    - Nombre del Tipo de Uso y Tipo de Zona
    - Propietarios activos
    - Conceptos de cobro asociados
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
       
        -- Validación de existencia de la propiedad
        IF NOT EXISTS
        (
            SELECT 1 
            FROM dbo.Propiedad AS p
            WHERE p.NumeroFinca = @inNumeroFinca
        )
        BEGIN
            SET @outResultCode = 3;
            RETURN;
        END;

        SET @outResultCode = 0;

        -- Datos de la propiedad
        SELECT
              p.NumeroFinca
            , p.NumeroMedidor
            , p.MetrosCuadrados
            , p.TipoUsoId
            , tu.Nombre AS TipoUsoNombre
            , p.TipoZonaId
            , tz.Nombre AS TipoZonaNombre
            , p.ValorFiscal
            , p.FechaRegistro
            , p.SaldoM3
            , p.SaldoM3UltimaFactura
        FROM dbo.Propiedad AS p
        INNER JOIN dbo.TipoUsoPropiedad AS tu 
            ON tu.Id = p.TipoUsoId
        INNER JOIN dbo.TipoZonaPropiedad AS tz
            ON tz.Id = p.TipoZonaId
        WHERE p.NumeroFinca = @inNumeroFinca;

        -- Propietarios activos
        SELECT
              per.ValorDocumento
            , per.Nombre
            , per.Email
            , per.Telefono
            , pp.FechaInicio
        FROM dbo.PropiedadPersona AS pp
        INNER JOIN dbo.Persona AS per
            ON per.Id = pp.PersonaId
        WHERE     pp.PropiedadId = @inNumeroFinca
              AND pp.FechaFin    IS NULL
        ORDER BY
            pp.FechaInicio;

        -- Conceptos de cobro asociados
        SELECT
              ccp.ConceptoCobroId
            , cc.Nombre
            , ccp.FechaAsociacion
        FROM dbo.ConceptoCobroPropiedad AS ccp
        INNER JOIN dbo.ConceptoCobro AS cc
            ON cc.Id = ccp.ConceptoCobroId
        WHERE ccp.PropiedadId = @inNumeroFinca
        ORDER BY
            ccp.ConceptoCobroId;
    END TRY

    BEGIN CATCH
        
        SET @outResultCode = 50010;

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

