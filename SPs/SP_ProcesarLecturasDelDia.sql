USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_ProcesarLecturasDelDia]    Script Date: 23/11/2025 17:12:04 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE   PROCEDURE [dbo].[SP_ProcesarLecturasDelDia](
    @inFecha DATE,
    @inFechaXml XML,
    @outResultCode INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- 1) extraer lecturas del XML a tabla variable @Lecturas
        DECLARE @Lecturas TABLE(
            NumeroMedidor VARCHAR(32),
            TipoMovimientoId INT,
            Valor DECIMAL(10,2)
        );

        INSERT INTO @Lecturas
        SELECT
            L.value('@numeroMedidor','varchar(32)'),
            L.value('@tipoMovimientoId','int'),
            L.value('@valor','decimal(10,2)')
        FROM @inFechaXml.nodes('/FechaOperacion/LecturasMedidor/Lectura') AS T(L);

        BEGIN TRANSACTION;

        -- 2) insertar en LecturaMedidor
        INSERT INTO dbo.LecturaMedidor(
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

        -- 3) actualizar saldos en Propiedad
        ;WITH DeltaPorMedidor AS (
        SELECT
            NumeroMedidor,
            SUM(
                CASE TipoMovimientoId
                    WHEN 1 THEN Valor            -- lectura normal suma
                    WHEN 2 THEN -Valor           -- crédito resta
                    WHEN 3 THEN Valor            -- débito suma
                END
            ) AS Delta
        FROM @Lecturas
        GROUP BY NumeroMedidor
    )
    UPDATE p
    SET p.SaldoM3 = p.SaldoM3 + d.Delta
    FROM dbo.Propiedad p
    INNER JOIN DeltaPorMedidor d
        ON d.NumeroMedidor = p.NumeroMedidor;


        COMMIT;

        SET @outResultCode=0;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        SET @outResultCode=50010;
        INSERT dbo.DBError
        (
            UserName,
            Number,
            State,
            Severity,
            Line,
            [Procedure],
            Message,
            DateTime
        
        ) 
        VALUES
        (
            'SP_ProcesarLecturasDelDia',
            ERROR_NUMBER(),
            ERROR_STATE(),
            ERROR_SEVERITY(),
            ERROR_LINE(),
            'SP_ProcesarLecturasDelDia',
            ERROR_MESSAGE(),
            GETDATE()
        
        );
    END CATCH
END
GO

