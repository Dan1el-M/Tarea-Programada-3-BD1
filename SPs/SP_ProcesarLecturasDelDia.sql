USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ProcesarLecturasDelDia]    Script Date: 26/11/2025 15:54:36 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_ProcesarLecturasDelDia]
(
      @inFecha       DATE
    , @inFechaXml    XML
    , @outResultCode INT OUTPUT
)
/*
SP que procesa las lecturas de medidor del día:
    - extrae lecturas desde el XML
    - inserta en LecturaMedidor
    - calcula delta de consumo por medidor
    - actualiza el saldo M3 de cada propiedad
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE @Lecturas TABLE
        (
              NumeroMedidor    VARCHAR(32)
            , TipoMovimientoId INT
            , Valor            DECIMAL(10,2)
        );

        INSERT INTO @Lecturas
        (
              NumeroMedidor
            , TipoMovimientoId
            , Valor
        )
        SELECT
              L.value('@numeroMedidor','VARCHAR(32)')
            , L.value('@tipoMovimientoId','INT')
            , L.value('@valor','DECIMAL(10,2)')
        FROM @inFechaXml.nodes('/FechaOperacion/LecturasMedidor/Lectura') AS T(L);

        BEGIN TRANSACTION;

        INSERT INTO dbo.LecturaMedidor
        (
              NumeroMedidor
            , TipoMovimientoId
            , FechaLectura
            , Valor
        )
        SELECT
              l.NumeroMedidor
            , l.TipoMovimientoId
            , @inFecha
            , l.Valor
        FROM @Lecturas AS l;

        ;WITH MovPorMedidor AS
        (
            SELECT
                  NumeroMedidor
                , TipoMovimientoId
                , Valor
            FROM @Lecturas
        )
        UPDATE p
        SET p.SaldoM3 =
                CASE m.TipoMovimientoId
                    WHEN 1 THEN m.Valor             -- lectura normal
                    WHEN 2 THEN p.SaldoM3 - m.Valor -- ajuste negativo
                    WHEN 3 THEN p.SaldoM3 + m.Valor -- ajuste positivo
                    ELSE p.SaldoM3                  -- por seguridad
                END
        FROM dbo.Propiedad AS p
        INNER JOIN MovPorMedidor AS m
            ON m.NumeroMedidor = p.NumeroMedidor;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;
    END TRY

    BEGIN CATCH

        IF ( @@TRANCOUNT > 0 )
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50012;

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

