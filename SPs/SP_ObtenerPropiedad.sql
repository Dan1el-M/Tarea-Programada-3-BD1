USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ObtenerPropiedad]    Script Date: 23/11/2025 17:11:22 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_ObtenerPropiedad]
(
    @inNumeroFinca   VARCHAR(64),
    @outResultCode   INT OUTPUT
)

/*
SP para mostrar los datos que tiene una propeidad, los datelles, los propietarios y los CC que tiene asignados
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Propiedad WHERE NumeroFinca = @inNumeroFinca)
        BEGIN
            SET @outResultCode = 3; -- no existe
            RETURN;
        END

        SET @outResultCode = 0;

        -- 1) Propiedad
        SELECT
            p.NumeroFinca, p.NumeroMedidor, p.MetrosCuadrados,
            p.TipoUsoId, p.TipoZonaId, p.ValorFiscal,
            p.FechaRegistro, p.SaldoM3, p.SaldoM3UltimaFactura
        FROM dbo.Propiedad p
        WHERE p.NumeroFinca = @inNumeroFinca;

        -- 2) Propietarios activos
        SELECT
            per.ValorDocumento, per.Nombre, per.Email, per.Telefono,
            pp.FechaInicio
        FROM dbo.PropiedadPersona pp
        INNER JOIN dbo.Persona per ON per.Id = pp.PersonaId
        WHERE pp.PropiedadId = @inNumeroFinca
          AND pp.FechaFin IS NULL
        ORDER BY pp.FechaInicio;

        -- 3) CC asociados (activos según el modelo actual)
        SELECT
            ccp.ConceptoCobroId,
            cc.Nombre,
            ccp.FechaAsociacion
        FROM dbo.ConceptoCobroPropiedad ccp
        INNER JOIN dbo.ConceptoCobro cc ON cc.Id = ccp.ConceptoCobroId
        WHERE ccp.PropiedadId = @inNumeroFinca
        ORDER BY ccp.ConceptoCobroId;

    END TRY
    BEGIN CATCH
        SET @outResultCode = 50052;

        INSERT dbo.DBError(
            UserName
            , Number
            , State
            , Severity
            , Line
            , [Procedure]
            , Message
            , DateTime
        )
        VALUES(
            'SP_ObtenerPropiedad'
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_ObtenerPropiedad'
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );
    END CATCH
END;
GO

