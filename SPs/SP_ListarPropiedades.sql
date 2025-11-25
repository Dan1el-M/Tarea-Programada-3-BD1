USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ListarPropiedades]    Script Date: 24/11/2025 20:19:07 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_ListarPropiedades]
(
     @inNumeroFinca     VARCHAR(64) = NULL
    ,@inValorDocumento  VARCHAR(64) = NULL
    ,@outResultCode     INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- 1) Sin filtros
        IF @inNumeroFinca IS NULL AND @inValorDocumento IS NULL
        BEGIN
            SET @outResultCode = 0;

            SELECT
                 p.NumeroFinca
                ,p.NumeroMedidor
                ,p.MetrosCuadrados
                ,p.TipoUsoId
                ,p.TipoZonaId
                ,p.ValorFiscal
                ,p.FechaRegistro
                ,p.SaldoM3
                ,p.SaldoM3UltimaFactura
            FROM dbo.Propiedad p
            ORDER BY p.NumeroFinca;

            RETURN;
        END


        -- 2) Buscar POR FINCA 
        IF @inNumeroFinca IS NOT NULL
        BEGIN
            SET @outResultCode = 0;

            SELECT
                 p.NumeroFinca
                ,p.NumeroMedidor
                ,p.MetrosCuadrados
                ,p.TipoUsoId
                ,p.TipoZonaId
                ,p.ValorFiscal
                ,p.FechaRegistro
                ,p.SaldoM3
                ,p.SaldoM3UltimaFactura
            FROM dbo.Propiedad p
            WHERE p.NumeroFinca LIKE @inNumeroFinca + '%'
            ORDER BY p.NumeroFinca;

            RETURN;
        END


        -- 3) Buscar por PROPIETARIO (cédula)
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Persona per
            WHERE per.ValorDocumento = @inValorDocumento
        )
        BEGIN
            SET @outResultCode = 4; -- persona no existe
            RETURN;
        END

        SET @outResultCode = 0;

        SELECT DISTINCT
             p.NumeroFinca
            ,p.NumeroMedidor
            ,p.MetrosCuadrados
            ,p.TipoUsoId
            ,p.TipoZonaId
            ,p.ValorFiscal
            ,p.FechaRegistro
            ,p.SaldoM3
            ,p.SaldoM3UltimaFactura
        FROM dbo.PropiedadPersona pp
        INNER JOIN dbo.Persona per
            ON per.Id = pp.PersonaId
        INNER JOIN dbo.Propiedad p
            ON p.NumeroFinca = pp.PropiedadId
        WHERE per.ValorDocumento = @inValorDocumento
          AND pp.FechaFin IS NULL
        ORDER BY p.NumeroFinca;

    END TRY
    BEGIN CATCH
        SET @outResultCode = 50051;

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
             'SP_ListarPropiedades'
            ,ERROR_NUMBER()
            ,ERROR_STATE()
            ,ERROR_SEVERITY()
            ,ERROR_LINE()
            ,'SP_ListarPropiedades'
            ,ERROR_MESSAGE()
            ,SYSDATETIME()
        );

        THROW;
    END CATCH
END;
GO

