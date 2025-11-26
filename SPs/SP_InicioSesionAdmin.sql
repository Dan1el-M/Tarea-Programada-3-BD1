USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_InicioSesionAdmin]    Script Date: 26/11/2025 15:53:15 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[SP_InicioSesionAdmin]
(
      @inNombreUsuario VARCHAR(64)
    , @inContrasena    VARCHAR(128)
    , @outResultCode   INT OUTPUT
)
/*
SP que valida credenciales del usuario administrador.
Retorna:
    0      -> credenciales correctas
    1      -> credenciales inválidas
    50008  -> error interno
*/
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        
        IF EXISTS
        (
            SELECT 1
            FROM dbo.Usuario AS u
            WHERE     u.NombreUsuario = @inNombreUsuario
                  AND u.Contrasena    = @inContrasena
        )
        BEGIN
            SET @outResultCode = 0;

            SELECT 
                  u.Id
                , u.NombreUsuario
            FROM dbo.Usuario AS u
            WHERE u.NombreUsuario = @inNombreUsuario;
        END
        ELSE
        BEGIN
            SET @outResultCode = 1;
        END;
    END TRY

    BEGIN CATCH
        
        SET @outResultCode = 50008;

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

