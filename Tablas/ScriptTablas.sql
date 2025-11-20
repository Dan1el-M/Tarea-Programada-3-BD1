/* =========================================================
   CATALOGOS Y PARAMETROS
   ========================================================= */



--*******************************************************************************************************************************************
--*******************************************************************************************************************************************
-- Script que si tiene las fechas, y se corrigió el foreign key de propiedades
--*******************************************************************************************************************************************
--*******************************************************************************************************************************************

-- Parámetros generales del sistema
CREATE TABLE dbo.ParametrosSistema(
  Nombre NVARCHAR(128) NOT NULL PRIMARY KEY,
  Valor  NVARCHAR(256) NOT NULL
);

CREATE TABLE dbo.TipoMovimientoLecturaMedidor(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Lectura, 2=Ajuste Crédito, 3=Ajuste Débito
  Nombre NVARCHAR(128) NOT NULL
);

CREATE TABLE dbo.TipoUsoPropiedad(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Habitación, 2=Comercial, 3=Industrial,
  Nombre NVARCHAR(128) NOT NULL                  -- 4=Lote Baldío, 5=Agrícola
);

CREATE TABLE dbo.TipoZonaPropiedad(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Residencial, 2=Agrícola, 3=Bosque,
  Nombre NVARCHAR(128) NOT NULL                  -- 4=Industrial, 5=Comercial
);

CREATE TABLE dbo.Usuario(
  Id     INT                    NOT NULL PRIMARY KEY,     -- Admin
  NombreUsuario NVARCHAR(128)   NOT NULL,
  Contrasena NVARCHAR(128)      NOT NULL
);

CREATE TABLE dbo.TipoAsociacion(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Asociar, 2=Desasociar
  Nombre NVARCHAR(128) NOT NULL
);

CREATE TABLE dbo.TipoMedioPago(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Efectivo, 2=Tarjeta
  Nombre NVARCHAR(128) NOT NULL
);

CREATE TABLE dbo.PeriodoMontoCC(                 -- Por simplicidad todos se cobran mensualmente
  Id     INT           NOT NULL PRIMARY KEY,
  Nombre NVARCHAR(128) NOT NULL,
  Dias   INT           NULL,
  QMeses INT           NULL,
  CONSTRAINT CK_PeriodoMontoCC_AlgunaVentana
    CHECK (Dias IS NOT NULL OR QMeses IS NOT NULL)
);

CREATE TABLE dbo.TipoMontoCC(
  Id     INT           NOT NULL PRIMARY KEY,     -- 1=Fijo, 2=Variable, 3=Porcentaje
  Nombre NVARCHAR(128) NOT NULL
);

/* =========================================================
   PERSONAS, PROPIEDADES Y USUARIOS
   ========================================================= */

-- Personas (físicas o jurídicas)
CREATE TABLE dbo.Persona(
  Id              INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
  ValorDocumento  VARCHAR(64)   NOT NULL UNIQUE,      -- viene del XML
  Nombre          NVARCHAR(128) NOT NULL,
  Email           NVARCHAR(128) NULL,
  Telefono        VARCHAR(32)   NULL,
  Fecha           DATE          NOT NULL
);

-- Propiedades
CREATE TABLE dbo.Propiedad(
  NumeroFinca          VARCHAR(64)    NOT NULL UNIQUE,  -- viene del XML
  NumeroMedidor        VARCHAR(32)    NOT NULL UNIQUE,         -- ej. M-1001
  MetrosCuadrados      DECIMAL(10,2)  NOT NULL,
  TipoUsoId            INT            NOT NULL,
  TipoZonaId           INT            NOT NULL,
  ValorFiscal          MONEY          NOT NULL,
  FechaRegistro        DATE           NOT NULL,
  SaldoM3              INT            NOT NULL DEFAULT(0),  -- x2
  SaldoM3UltimaFactura INT            NOT NULL DEFAULT(0),  -- No sabemos si va esto ((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((


  CONSTRAINT FK_Propiedad_TipoUso  FOREIGN KEY (TipoUsoId)
    REFERENCES dbo.TipoUsoPropiedad(Id),
  CONSTRAINT FK_Propiedad_TipoZona FOREIGN KEY (TipoZonaId)
    REFERENCES dbo.TipoZonaPropiedad(Id)
);

-- Relación Propiedad-Persona (propietarios a lo largo del tiempo)
CREATE TABLE dbo.PropiedadPersona(   -- ****** Esta hay que revisarla bien, porque no sabemos si faltan campos
  PropiedadId      VARCHAR(64)  NOT NULL,
  PersonaId        INT          NOT NULL,
  FechaInicio      DATE         NOT NULL,
  FechaFin         DATE         NULL,
  TipoAsociacionId INT          NOT NULL,  -- viene del XML de movimientos

  CONSTRAINT PK_PersonaPropiedad PRIMARY KEY (PropiedadId, PersonaId, FechaInicio),
  CONSTRAINT FK_PP_Propiedad      FOREIGN KEY (PropiedadId)
    REFERENCES dbo.Propiedad(NumeroFinca),
  CONSTRAINT FK_PP_Persona        FOREIGN KEY (PersonaId)
    REFERENCES dbo.Persona(Id),
  CONSTRAINT FK_PP_TipoAsociacion FOREIGN KEY (TipoAsociacionId)
    REFERENCES dbo.TipoAsociacion(Id)
);

/* =========================================================
   CONCEPTOS DE COBRO Y ASIGNACIÓN A PROPIEDADES
   ========================================================= */

CREATE TABLE dbo.ConceptoCobro( -- viene del XML de catalogos de CCs
  Id                   INT           NOT NULL PRIMARY KEY,
  Nombre               NVARCHAR(128) NOT NULL,
  TipoMontoCCId        INT           NOT NULL,
  PeriodoMontoCCId     INT           NOT NULL,
  ValorMinimo          MONEY         NULL,
  ValorMinimoM3        INT           NULL,
  ValorFijoM3Adicional MONEY         NULL,
  ValorPorcentual      DECIMAL(5,2)  NULL,  -- 0.01 = 1%
  ValorFijo            MONEY         NULL,
  ValorM2Minimo        INT           NULL,
  ValorTractosM2       INT           NULL,
  Activo               BIT           NOT NULL DEFAULT(1),

  CONSTRAINT FK_ConceptoCobro_PeriodoMontoCC FOREIGN KEY (PeriodoMontoCCId)
    REFERENCES dbo.PeriodoMontoCC(Id),
  CONSTRAINT FK_ConceptoCobro_TipoMontoCC FOREIGN KEY (TipoMontoCCId)
    REFERENCES dbo.TipoMontoCC(Id),

  -- Si usa porcentaje, debe estar entre 0 y 1
  CONSTRAINT CK_ConceptoCobro_Porc CHECK (
    ValorPorcentual IS NULL OR (ValorPorcentual BETWEEN 0 AND 1)
  ),

  -- Ningún valor monetario mínimo / fijo debe ser negativo
  CONSTRAINT CK_ConceptoCobro_NoNeg CHECK (
    ISNULL(ValorMinimo,0)          >= 0 AND
    ISNULL(ValorFijo,0)            >= 0 AND
    ISNULL(ValorFijoM3Adicional,0) >= 0 AND
    ISNULL(ValorM2Minimo,0)        >= 0 AND
    ISNULL(ValorTractosM2,0)       >= 0
  )
);

-- Asignación de Conceptos de Cobro a Propiedades
-- (estado actual de qué CC aplica a qué propiedad)
CREATE TABLE dbo.ConceptoCobroPropiedad(
  PropiedadId     VARCHAR(64)  NOT NULL,
  ConceptoCobroId INT  NOT NULL,
  FechaAsociacion DATE NOT NULL,
  Activo          BIT  NOT NULL DEFAULT(1),

  CONSTRAINT PK_PropiedadConceptoCobro PRIMARY KEY (PropiedadId, ConceptoCobroId),
  CONSTRAINT FK_PCC_Propiedad     FOREIGN KEY (PropiedadId)
    REFERENCES dbo.Propiedad(NumeroFinca),
  CONSTRAINT FK_PCC_ConceptoCobro FOREIGN KEY (ConceptoCobroId)
    REFERENCES dbo.ConceptoCobro(Id)
);

/* =========================================================
   FACTURAS, DETALLES Y PAGOS
   ========================================================= */

-- Estados de factura simples (si no quieres otro catálogo)
-- 1=Pendiente, 2=Pagada
CREATE TABLE dbo.Factura(
  Id                  INT         NOT NULL IDENTITY(1,1) PRIMARY KEY,
  PropiedadId         VARCHAR(64) NOT NULL,
  FechaFactura        DATE        NOT NULL,
  FechaLimitePagar    DATE        NOT NULL,
  TotalAPagarOriginal MONEY       NOT NULL DEFAULT(0),
  TotalAPagarFinal    MONEY       NOT NULL DEFAULT(0),
  EstadoFacturaId     INT         NOT NULL DEFAULT(1),

  CONSTRAINT FK_Factura_Propiedad FOREIGN KEY (PropiedadId)
    REFERENCES dbo.Propiedad(NumeroFinca),
  CONSTRAINT CK_Factura_Estado CHECK (EstadoFacturaId IN (1,2))
);

CREATE TABLE dbo.DetalleFactura(
  Id              INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
  FacturaId       INT           NOT NULL,
  ConceptoCobroId INT           NOT NULL,
  Monto           MONEY         NOT NULL,
  Descripcion     NVARCHAR(256) NULL,

  CONSTRAINT FK_DetalleFactura_Factura FOREIGN KEY (FacturaId)
    REFERENCES dbo.Factura(Id),
  CONSTRAINT FK_DetalleFactura_ConceptoCobro FOREIGN KEY (ConceptoCobroId)
    REFERENCES dbo.ConceptoCobro(Id)
);

CREATE TABLE dbo.Pago(
  Id               INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
  FacturaId        INT           NOT NULL,
  TipoMedioPagoId  INT           NOT NULL,
  FechaPago        DATE          NOT NULL,
  MontoPagado      MONEY         NOT NULL,
  NumeroReferencia VARCHAR(128)  NOT NULL,   -- RCPT-202507-F-0001

  CONSTRAINT FK_Pago_Factura FOREIGN KEY (FacturaId)
    REFERENCES dbo.Factura(Id),
  CONSTRAINT FK_Pago_TipoMedioPago FOREIGN KEY (TipoMedioPagoId)
    REFERENCES dbo.TipoMedioPago(Id)
);

/* =========================================================
   LECTURAS DE MEDIDOR
   ========================================================= */

CREATE TABLE dbo.LecturaMedidor(
  Id               INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
  NumeroMedidor    VARCHAR(32)   NOT NULL,
  TipoMovimientoId INT           NOT NULL,         -- FK a catálogo
  FechaLectura     DATE          NULL,             
  Valor            DECIMAL(10,2) NOT NULL,

  CONSTRAINT FK_LecturaMedidor_TipoMovimiento FOREIGN KEY (TipoMovimientoId)
    REFERENCES dbo.TipoMovimientoLecturaMedidor(Id),

  CONSTRAINT FK_LecturaMedidor_Propiedad FOREIGN KEY (NumeroMedidor)
    REFERENCES dbo.Propiedad(NumeroMedidor)
);

/* =========================================================
   ORDENES DE CORTA Y RECONEXION
   ========================================================= */

-- 1=Pendiente, 2=Ejecutada
CREATE TABLE dbo.OrdenCorta(
  Id             INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
  PropiedadId    VARCHAR(64)  NOT NULL,
  FacturaId      INT          NOT NULL,
  FechaGenerada  DATE         NOT NULL,
  FechaEjecutada DATE         NULL,
  Estado         INT          NOT NULL DEFAULT(1),

  CONSTRAINT FK_OrdenCorta_Propiedad FOREIGN KEY (PropiedadId)
    REFERENCES dbo.Propiedad(NumeroFinca),
  CONSTRAINT FK_OrdenCorta_Factura FOREIGN KEY (FacturaId)
    REFERENCES dbo.Factura(Id),
  CONSTRAINT CK_OrdenCorta_Estado CHECK (Estado IN (1,2))
);

CREATE TABLE dbo.OrdenReconexion(
  Id             INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
  PropiedadId    VARCHAR(64)   NOT NULL,
  FacturaId      INT           NOT NULL,
  FechaGenerada  DATE          NOT NULL,
  FechaEjecutada DATE          NULL,
  Estado         INT           NOT NULL DEFAULT(1),

  CONSTRAINT FK_OrdenReconexion_Propiedad FOREIGN KEY (PropiedadId)
    REFERENCES dbo.Propiedad(NumeroFinca),
  CONSTRAINT FK_OrdenReconexion_Factura FOREIGN KEY (FacturaId)
    REFERENCES dbo.Factura(Id),
  CONSTRAINT CK_OrdenReconexion_Estado CHECK (Estado IN (1,2))
);

/* =========================================================
   TABLA PARA MANEJO DE ERRORES
   ========================================================= */

CREATE TABLE [dbo].[DBError](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[UserName] [nvarchar](50) NULL,
	[Number] [int] NULL,
	[State] [int] NULL,
	[Severity] [int] NULL,
	[Line] [int] NULL,
	[Procedure] [nvarchar](128) NULL,
	[Message] [nvarchar](4000) NULL,
	[DateTime] [datetime2](7) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[DBError] ADD  DEFAULT (sysdatetime()) FOR [DateTime]
GO

/* =========================================================
   INDICES DE APOYO / CALIDAD DE DATOS
   ========================================================= */

-- Unicidad en catálogos y entidades clave
CREATE UNIQUE INDEX UX_ConceptoCobro_Nombre       ON dbo.ConceptoCobro(Nombre);
CREATE UNIQUE INDEX UX_Propiedad_NumeroFinca      ON dbo.Propiedad(NumeroFinca);
CREATE UNIQUE INDEX UX_Persona_ValorDocumento     ON dbo.Persona(ValorDocumento);
CREATE UNIQUE INDEX UX_TipoZonaPropiedad_Nombre   ON dbo.TipoZonaPropiedad(Nombre);
CREATE UNIQUE INDEX UX_TipoUsoPropiedad_Nombre    ON dbo.TipoUsoPropiedad(Nombre);
CREATE UNIQUE INDEX UX_TipoMedioPago_Nombre       ON dbo.TipoMedioPago(Nombre);
CREATE UNIQUE INDEX UX_TipoMovLectura_Nombre      ON dbo.TipoMovimientoLecturaMedidor(Nombre);

-- Indices para consultas típicas
CREATE INDEX IX_Factura_Propiedad ON dbo.Factura(PropiedadId);
CREATE INDEX IX_Factura_Estado    ON dbo.Factura(EstadoFacturaId);
CREATE INDEX IX_Pago_Factura      ON dbo.Pago(FacturaId);
CREATE INDEX IX_Lectura_Medidor   ON dbo.LecturaMedidor(NumeroMedidor, FechaLectura);