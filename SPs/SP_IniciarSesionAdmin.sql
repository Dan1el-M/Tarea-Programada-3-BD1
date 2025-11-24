USE [Tarea 3 BD1]
GO

/****** Object:  StoredProcedure [dbo].[SP_InicioSesionAdmin]    Script Date: 23/11/2025 17:10:46 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[SP_InicioSesionAdmin]
(
    @inNombreUsuario VARCHAR(64),
    @inContrasena    VARCHAR(128),
    @outResultCode   INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario u
            WHERE u.NombreUsuario = @inNombreUsuario
              AND u.Contrasena    = @inContrasena
        )
        BEGIN
            SET @outResultCode = 0; -- OK

            -- opcional: devolver el admin logueado
            SELECT u.Id, u.NombreUsuario
            FROM dbo.Usuario u
            WHERE u.NombreUsuario = @inNombreUsuario;
        END
        ELSE
        BEGIN
            SET @outResultCode = 1; -- credenciales inválidas
        END
    END TRY
    BEGIN CATCH
        SET @outResultCode = 50050;

        INSERT dbo.DBError(
            UserName
            , Number
            , State
            , Severity
            , Line
            ,[Procedure]
            , Message
            , DateTime
        )
        VALUES(
            'SP_InicioSesionAdmin'
            ,
            ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , 'SP_InicioSesionAdmin'
            , ERROR_MESSAGE()
            , SYSDATETIME()
        );
    END CATCH
END;
GO

