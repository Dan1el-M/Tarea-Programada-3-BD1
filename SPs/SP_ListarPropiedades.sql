USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ListarPropiedades]    Script Date: 26/11/2025 15:53:34 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_ListarPropiedades]
(
      @inNumeroFinca    VARCHAR(64) = NULL
    , @inValorDocumento VARCHAR(64) = NULL
    , @outResultCode    INT         OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- Consulta sin filtros
        IF ( @inNumeroFinca IS NULL AND @inValorDocumento IS NULL )
        BEGIN
            SET @outResultCode = 0;

            SELECT
                  p.NumeroFinca
                , p.NumeroMedidor
                , p.MetrosCuadrados
                , p.TipoUsoId
                , p.TipoZonaId
                , p.ValorFiscal
                , p.FechaRegistro
                , p.SaldoM3
                , p.SaldoM3UltimaFactura
                , Propietarios =
                    (
                        SELECT STRING_AGG(CONVERT(VARCHAR(20), per.ValorDocumento), ', ')
                        FROM dbo.PropiedadPersona AS pp
                        INNER JOIN dbo.Persona AS per
                            ON per.Id = pp.PersonaId
                        WHERE     pp.PropiedadId = p.NumeroFinca
                              AND pp.FechaFin IS NULL
                    )
            FROM dbo.Propiedad AS p
            ORDER BY
                p.NumeroFinca;

            RETURN;
        END;

        -- Búsqueda por número de finca
        IF ( @inNumeroFinca IS NOT NULL )
        BEGIN
            SET @outResultCode = 0;

            SELECT
                  p.NumeroFinca
                , p.NumeroMedidor
                , p.MetrosCuadrados
                , p.TipoUsoId
                , p.TipoZonaId
                , p.ValorFiscal
                , p.FechaRegistro
                , p.SaldoM3
                , p.SaldoM3UltimaFactura
                , Propietarios =
                    (
                        SELECT STRING_AGG(CONVERT(VARCHAR(20), per.ValorDocumento), ', ')
                        FROM dbo.PropiedadPersona AS pp
                        INNER JOIN dbo.Persona AS per
                            ON per.Id = pp.PersonaId
                        WHERE     pp.PropiedadId = p.NumeroFinca
                              AND pp.FechaFin IS NULL
                    )
            FROM dbo.Propiedad AS p
            WHERE p.NumeroFinca LIKE @inNumeroFinca + '%'
            ORDER BY
                p.NumeroFinca;

            RETURN;
        END;

        -- Búsqueda por propietario (cédula)
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Persona AS per
            WHERE per.ValorDocumento = @inValorDocumento
        )
        BEGIN
            SET @outResultCode = 4; -- persona no existe
            RETURN;
        END;

        SET @outResultCode = 0;

        SELECT DISTINCT
              p.NumeroFinca
            , p.NumeroMedidor
            , p.MetrosCuadrados
            , p.TipoUsoId
            , p.TipoZonaId
            , p.ValorFiscal
            , p.FechaRegistro
            , p.SaldoM3
            , p.SaldoM3UltimaFactura
            , Propietarios =
                (
                    SELECT STRING_AGG(CONVERT(VARCHAR(20), per2.ValorDocumento), ', ')
                    FROM dbo.PropiedadPersona AS pp2
                    INNER JOIN dbo.Persona AS per2
                        ON per2.Id = pp2.PersonaId
                    WHERE     pp2.PropiedadId = p.NumeroFinca
                          AND pp2.FechaFin IS NULL
                )
        FROM dbo.PropiedadPersona AS pp
        INNER JOIN dbo.Persona AS per
            ON per.Id = pp.PersonaId
        INNER JOIN dbo.Propiedad AS p
            ON p.NumeroFinca = pp.PropiedadId
        WHERE     per.ValorDocumento = @inValorDocumento
              AND pp.FechaFin IS NULL
        ORDER BY
            p.NumeroFinca;

    END TRY

    BEGIN CATCH
        SET @outResultCode = 50009;

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

