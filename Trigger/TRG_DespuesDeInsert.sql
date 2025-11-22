USE [Tarea 3 BD1]
GO

/****** Object:  Trigger [dbo].[TRG_DespuesDeInsert]    Script Date: 21/11/2025 11:45:19 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   TRIGGER [dbo].[TRG_DespuesDeInsert]

--SI QUIERO PONER UN OUTRESULTCODE LO HAGO ACA?
--@outResultCode INT OUTPUT  los trigger no tienen parametros

ON [dbo].[Propiedad]

AFTER INSERT

AS

BEGIN

	SET NOCOUNT ON
	BEGIN TRY
	-- Se le asigna el CC de impuesto sobre la propiedad a todas.
	INSERT INTO ConceptoCobroPropiedad(
		PropiedadId
		,ConceptoCobroId
		,FechaAsociacion
		)

	SELECT
		T.NumeroFinca
		,3                -- Id de Impuestos
		,SYSDATETIME()
	FROM inserted AS T;

	-- Consumo de agua: solo si TipoUsoId es habitación, comercial o industrial
	IF EXISTS (SELECT 1 FROM inserted WHERE TipoUsoId IN (1,2,3))
	-- IF EXISTS: revisa todas las filas de 'inserted' y verifica si hay
	-- al menos una propiedad cuyo TipoUsoId sea 1, 2 o 3. (osea con que exista un 1 ya entra porque debmos procesarlo)

	BEGIN
		INSERT INTO ConceptoCobroPropiedad(
			PropiedadId
			,ConceptoCobroId
			,FechaAsociacion
		)
		SELECT
			i.NumeroFinca
			,1            -- Id de Consumo de agua
			,SYSDATETIME()               
		FROM inserted AS i
		WHERE i.TipoUsoId IN (1,2,3);
	END;

	-- Todas menos agricola -> Recolección basura.
	IF EXISTS (SELECT 1 FROM inserted WHERE TipoUsoId < 5)
	BEGIN
		INSERT INTO ConceptoCobroPropiedad(
			PropiedadId
			,ConceptoCobroId
			,FechaAsociacion
		)
		SELECT
			i.NumeroFinca
			,4			-- Id de RecolecciónBasura
			,SYSDATETIME()
		FROM inserted AS i
		WHERE i.TipoUsoId <> 5;
		PRINT('3 completado')
	END


	-- Mantenimiento de parque IF TipoZona(residencial or comercial).
	IF EXISTS (SELECT 1 FROM inserted WHERE TipoZonaId IN (1,5))
	BEGIN
		INSERT INTO ConceptoCobroPropiedad(
			PropiedadId
			,ConceptoCobroId
			,FechaAsociacion
		)
		SELECT
			i.NumeroFinca
			,5                -- Id  de MantenimientoParques
			,SYSDATETIME()
		FROM inserted AS i
		WHERE i.TipoZonaId IN (1,5);
		PRINT('4 completado')
	END

	END TRY

	BEGIN CATCH
		DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
		RAISERROR(@ErrMsg, 16, 1);
	
	END CATCH

END
GO

ALTER TABLE [dbo].[Propiedad] ENABLE TRIGGER [TRG_DespuesDeInsert]
GO

