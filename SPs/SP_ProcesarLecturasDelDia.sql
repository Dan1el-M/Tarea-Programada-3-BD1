USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ProcesarLecturasDelDia]    Script Date: 24/11/2025 20:46:36 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_ProcesarLecturasDelDia]
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
              L.value('@numeroMedidor','varchar(32)')
            , L.value('@tipoMovimientoId','int')
            , L.value('@valor','decimal(10,2)')
        FROM @inFechaXml.nodes('/FechaOperacion/LecturasMedidor/Lectura') AS T(L);

      
        --  Transacción atómica 
        BEGIN TRANSACTION;

        INSERT INTO dbo.LecturaMedidor
        (
              NumeroMedidor
            , TipoMovimientoId
            , FechaLectura
            , Valor
        )
        SELECT
              NumeroMedidor
            , TipoMovimientoId
            , @inFecha
            , Valor
        FROM @Lecturas;


        -- 3) Actualizar saldo M3
        ;WITH DeltaPorMedidor AS
        (
            SELECT
                NumeroMedidor,
                SUM(
                    CASE TipoMovimientoId
                        WHEN 1 THEN Valor     -- lectura normal suma
                        WHEN 2 THEN -Valor    -- crédito resta
                        WHEN 3 THEN Valor     -- débito suma
                    END
                ) AS Delta
            FROM @Lecturas
            GROUP BY NumeroMedidor
        )
        UPDATE p
            SET p.SaldoM3 = d.Delta
        FROM dbo.Propiedad p
        INNER JOIN DeltaPorMedidor d
            ON d.NumeroMedidor = p.NumeroMedidor;

        COMMIT TRANSACTION;

        SET @outResultCode = 0;
        RETURN;

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

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
              'SP_ProcesarLecturasDelDia'
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_ProcesarLecturasDelDia'
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );

        THROW;

    END CATCH
END;
GO

