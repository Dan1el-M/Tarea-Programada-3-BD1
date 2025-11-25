<template>
  <div class="page">
    <button class="btn ghost" @click="volver">← Volver</button>

    <!-- Tarjeta propiedad -->
    <section class="card" v-if="propiedad">
      <div class="prop-grid">
        <div>
          <div class="label">Finca</div>
          <div class="value">{{ propiedad.NumeroFinca }}</div>
        </div>
        <div>
          <div class="label">Medidor</div>
          <div class="value">{{ propiedad.NumeroMedidor }}</div>
        </div>
        <div>
          <div class="label">Uso</div>
          <div class="value">{{ usoNombre }}</div>
        </div>
        <div>
          <div class="label">Zona</div>
          <div class="value">{{ zonaNombre }}</div>
        </div>
        <div>
          <div class="label">Área</div>
          <div class="value">{{ propiedad.MetrosCuadrados }} m²</div>
        </div>
        <div>
          <div class="label">Valor fiscal</div>
          <div class="value">{{ fmtCRC(propiedad.ValorFiscal) }}</div>
        </div>
        <div>
          <div class="label">Saldo m³</div>
          <div class="value">{{ propiedad.SaldoM3 }}</div>
        </div>
        <div>
          <div class="label">Fecha registro</div>
          <div class="value">{{ fmtDate(propiedad.FechaRegistro) }}</div>
        </div>
      </div>
    </section>

    <!-- Facturas -->
    <section class="card">
      <div class="tabs">
        <button class="tab" :class="{active: tab==='pendientes'}" @click="tab='pendientes'">
          Pendientes ({{ pendientes.length }})
        </button>
        <button class="tab" :class="{active: tab==='pagadas'}" @click="tab='pagadas'">
          Pagadas ({{ pagadas.length }})
        </button>
      </div>

      <!-- Botón pagar -->
      <div class="pay-bar" v-if="tab==='pendientes'">
        <button class="btn primary" :disabled="!oldestPending" @click="abrirPagoOldest">
          Pagar factura más vieja pendiente
        </button>

        <span class="small" v-if="oldestPending">
          #{{ oldestPending.NumeroFactura }} - {{ fmtDate(oldestPending.FechaFactura) }}
        </span>
      </div>

      <table class="table">
        <thead>
          <tr>
            <th>#Factura</th>
            <th>Fecha</th>
            <th>Vence</th>
            <th>Total final</th>
            <th>Estado</th>
            <th>Acción</th>
          </tr>
        </thead>

        <!-- Pendientes -->
        <tbody v-if="tab==='pendientes'">
          <tr v-for="f in pendientes" :key="f.NumeroFactura">
            <td>{{ f.NumeroFactura }}</td>
            <td>{{ fmtDate(f.FechaFactura) }}</td>
            <td>{{ fmtDate(f.FechaLimitePagar) }}</td>
            <td>{{ fmtCRC(f.TotalAPagarFinal) }}</td>
            <td>Pendiente</td>

            <td>
              <button class="btn small" @click="abrirDetalle(f)">Ver detalle</button>
            </td>
          </tr>

          <tr v-if="pendientes.length===0">
            <td colspan="6" class="empty">No hay facturas pendientes</td>
          </tr>
        </tbody>

        <!-- Pagadas -->
        <tbody v-else>
        <tr v-for="f in pagadas" :key="f.NumeroFactura">
          <td>{{ f.NumeroFactura }}</td>
          <td>{{ fmtDate(f.FechaFactura) }}</td>
          <td>{{ fmtDate(f.FechaLimitePagar) }}</td>
          <td>{{ fmtCRC(f.TotalAPagarFinal) }}</td>
          <td>
            Pagada<br />
            <small style="color:#555;">
              {{ fmtDate(f.FechaPago) }}
            </small>
          </td>

          <td>
            <button class="btn small" @click="abrirDetalle(f)">Ver detalle</button>
          </td>
        </tr>
      </tbody>
      </table>

      <p class="hint small" v-if="tab==='pendientes' && pendientes.length">
        * Solo se habilita el pago de la más vieja pendiente.
      </p>
    </section>

    <!-- Modal PAGO -->
    <div v-if="showPago" class="modal-backdrop" @click.self="cerrarPago">
      <div class="modal">
        <h3>Confirmar pago</h3>

        <div class="modal-info">
          <div><b>Finca:</b> {{ propiedad.NumeroFinca }}</div>
          <div><b>#Factura:</b> {{ facturaActual.NumeroFactura }}</div>
          <div><b>Fecha:</b> {{ fmtDate(facturaActual.FechaFactura) }}</div>
          <div><b>Vence:</b> {{ fmtDate(facturaActual.FechaLimitePagar) }}</div>
        </div>

        <div class="totals" v-if="detalle.length">
        <div class="row" v-for="(d, i) in detalle" :key="i">
          <span>
            {{ d.NombreCC || d.Descripcion }}
            <template v-if="d.ConsumoM3 != null">
              ({{ d.ConsumoM3 }} m³)
            </template>
          </span>

          <span>{{ fmtCRC(d.Monto ?? d.Total ?? d.Valor ?? d.MontoCC ?? 0) }}</span>
        </div>

        <hr />
      </div>

        <div v-else class="small" style="margin:.6rem 0; color:#777;">
          No se encontraron líneas de detalle para esta factura.
        </div>

        <div class="form">
          <label>Medio de pago</label>
          <div class="radio-row">
            <label><input type="radio" v-model="medioPagoId" :value="1" /> Efectivo</label>
            <label><input type="radio" v-model="medioPagoId" :value="2" /> Tarjeta</label>
          </div>

          <label>Referencia (auto-generada)</label>
          <div class="ref-box">{{ referencia }}</div>
        </div>

        <div class="modal-actions">
          <button class="btn" @click="cerrarPago">Cancelar</button>
          <button class="btn primary" @click="confirmarPago">Confirmar pago</button>
        </div>
      </div>
    </div>

    <!-- Modal DETALLE -->
    <div v-if="showDetalle" class="modal-backdrop" @click.self="cerrarDetalle">
      <div class="modal">
        <h3>Detalle de factura</h3>

        <div class="modal-info">
          <div><b>#Factura:</b> {{ facturaDetalleActual.NumeroFactura }}</div>
          <div><b>Fecha:</b> {{ fmtDate(facturaDetalleActual.FechaFactura) }}</div>
          <div><b>Vence:</b> {{ fmtDate(facturaDetalleActual.FechaLimitePagar) }}</div>
        </div>

        <div class="totals" v-if="detalle.length">
          <div class="row" v-for="(d, i) in detalle" :key="i">
            <span>{{ d.Descripcion }}</span>

            <span>{{ fmtCRC(d.Monto ?? d.Total ?? d.Valor ?? d.MontoCC ?? 0) }}</span>
          </div>

          <hr />

          <div class="row big">
            <span>Total</span>
            <span>{{ fmtCRC(facturaDetalleActual.TotalAPagarFinal) }}</span>
          </div>

        </div>

        <div v-else class="small" style="margin:.6rem 0; color:#777;">
          No se encontraron líneas de detalle para esta factura.
        </div>

        <div class="modal-actions">
          <button class="btn" @click="cerrarDetalle">Cerrar</button>
        </div>
      </div>
    </div>

    <!-- Toast -->
    <div v-if="msg" class="toast">{{ msg }}</div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "../axios";

const route = useRoute();
const router = useRouter();

const propiedad = ref(null);
const facturas = ref([]);
const tab = ref("pendientes");

const detalle = ref([]);

const showPago = ref(false);
const facturaActual = ref(null);
const medioPagoId = ref(1);
const referencia = ref("");
const pagoError = ref("");

const showDetalle = ref(false);
const facturaDetalleActual = ref(null);

const msg = ref("");

const fmtCRC = (n) => new Intl.NumberFormat("es-CR", { style: "currency", currency: "CRC", maximumFractionDigits: 0 }).format(Number(n));
const fmtDate = (d) => {
  if (!d) return "-";
  const [y, m, day] = d.split("-").map(Number);
  return new Date(y, m - 1, day).toLocaleDateString("es-CR");
};

const cargar = async () => {
  const finca = route.params.numeroFinca;
  const det = await api.get(`/propiedades/${finca}`);
  propiedad.value = det.data.propiedad;

  const fac = await api.get(`/propiedades/${finca}/facturas`);
  facturas.value = fac.data;
};

const cargarDetalleFactura = async (num) => {
  const resp = await api.get(`/facturas/${num}/detalle`);
  detalle.value = resp.data;
};

// Computados
const pendientes = computed(() => facturas.value.filter(f => f.EstadoFacturaId === 1));
const pagadas     = computed(() => facturas.value.filter(f => f.EstadoFacturaId !== 1));
const oldestPending = computed(() =>
  pendientes.value.length ? [...pendientes.value].sort((a,b) => new Date(a.FechaFactura)-new Date(b.FechaFactura))[0] : null
);

const usoNombre = computed(() => propiedad.value?.TipoUsoNombre);
const zonaNombre = computed(() => propiedad.value?.TipoZonaNombre);

// Acciones
const abrirDetalle = async (f) => {
  facturaDetalleActual.value = f;
  await cargarDetalleFactura(f.NumeroFactura);
  showDetalle.value = true;
};
const cerrarDetalle = () => (showDetalle.value = false);

const abrirPagoOldest = async () => {
  facturaActual.value = oldestPending.value;
  referencia.value = `REF-${propiedad.value.NumeroFinca.replace(/[^A-Za-z0-9]/g,"")}-${facturaActual.value.NumeroFactura}-${Date.now()}`;
  await cargarDetalleFactura(facturaActual.value.NumeroFactura);
  showPago.value = true;
};

const cerrarPago = () => (showPago.value = false);

const confirmarPago = async () => {
  try {
    await api.post("/facturas/pagar", {
      numeroFinca: propiedad.value.NumeroFinca,
      tipoMedioPagoId: medioPagoId.value,
      numeroReferencia: referencia.value,
      fechaPago: null
    });

    msg.value = `Pago realizado correctamente Ref: ${referencia.value}`;
    setTimeout(() => (msg.value = ""), 1500);

    showPago.value = false;
    cargar();
  } catch (e) {
    pagoError.value = "Error al procesar el pago";
  }
};

const volver = () => router.push("/propiedades");

onMounted(cargar);
</script>

<style scoped>
.page { padding: 1.2rem; background:#f5f6f8; min-height:100vh; font-family:system-ui; }
.card {
  background:white; padding:1rem 1.2rem; border-radius:12px;
  box-shadow:0 2px 8px rgba(0,0,0,.06); margin-bottom:1rem;
}

.prop-grid {
  display:grid; gap:.8rem 1.2rem;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
}
.label { font-size:.85rem; color:#666; }
.value { font-weight:800; font-size:1.05rem; }

.tabs { display:flex; gap:.5rem; margin-bottom:.6rem; }
.tab {
  border:none; background:#eef0f3; padding:.45rem .8rem; border-radius:8px;
  cursor:pointer; font-weight:700;
}
.tab.active { background:#1feb85; color:white; }

.pay-bar{
  display:flex; align-items:center; gap:1rem;
  margin:.4rem 0 .8rem;
}

.table { width:100%; border-collapse:collapse; }
.table th, .table td { border-bottom:1px solid #eef0f3; padding:.6rem .5rem; text-align:left; }
.empty { text-align:center; padding:1rem; color:#777; }

.btn {
  padding:.55rem .9rem; border:1px solid #cfd2d8;
  background:white; border-radius:8px; cursor:pointer; font-weight:600;
}
.btn.primary { background:#1f6feb; color:white; border-color:#1f6feb; }
.btn.ghost { background:transparent; border:none; color:#1f6feb; font-weight:700; cursor:pointer; }

.hint { color:#666; margin-top:.6rem; }
.hint.small, .small { font-size:.9rem; color:#666; }

/* ✅ Detalle */
.totals { margin:.8rem 0; }
.row { display:flex; justify-content:space-between; padding:.2rem 0; }
.row.big { font-weight:800; font-size:1.05rem; }
hr { border:none; border-top:1px solid #eee; margin:.4rem 0; }

/* Modal */
.modal-backdrop{
  position:fixed; inset:0; background:rgba(0,0,0,.35);
  display:grid; place-items:center; padding:1rem;
}
.modal{
  background:white; width:520px; max-width:100%;
  border-radius:12px; padding:1rem 1.2rem;
  box-shadow:0 8px 30px rgba(0,0,0,.25);
}
.modal-info{ display:grid; gap:.25rem; margin:.6rem 0; }
.form label{ font-weight:700; display:block; margin-top:.6rem; }
.form input{
  width:100%; margin-top:.25rem; padding:.55rem .6rem;
  border:1px solid #d7d9dd; border-radius:8px;
}
.radio-row{ display:flex; gap:1rem; margin-top:.3rem; }
.modal-actions{ display:flex; justify-content:flex-end; gap:.6rem; margin-top:1rem; }
.error{ color:#b00020; margin-top:.6rem; font-weight:700; }

.toast{
  position:fixed; bottom:18px; right:18px;
  background:#111827; color:white; padding:.7rem 1rem;
  border-radius:10px; box-shadow:0 6px 20px rgba(0,0,0,.25);
}
</style>
