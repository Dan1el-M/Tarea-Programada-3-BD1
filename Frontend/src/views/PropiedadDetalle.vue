<template>
  <div style="padding:2rem;">
    <button @click="$router.back()">← volver</button>
    <h2>Finca {{numeroFinca}}</h2>

    <div v-if="propiedad">
      <p><b>Medidor:</b> {{propiedad.NumeroMedidor}}</p>
      <p><b>Saldo m3:</b> {{propiedad.SaldoM3}}</p>
      <p><b>Valor fiscal:</b> {{propiedad.ValorFiscal}}</p>
    </div>

    <h3>Conceptos de cobro activos</h3>
    <ul>
      <li v-for="cc in ccs" :key="cc.Id">
        {{cc.Nombre}}
      </li>
    </ul>

    <h3>Facturas</h3>
    <table border="1" cellpadding="6" style="width:100%;">
      <thead>
        <tr>
          <th>Id</th><th>Fecha</th><th>Límite</th><th>Total</th><th>Estado</th><th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="f in facturas" :key="f.Id">
          <td>{{f.Id}}</td>
          <td>{{f.FechaFactura}}</td>
          <td>{{f.FechaLimitePagar}}</td>
          <td>{{f.TotalAPagarFinal}}</td>
          <td>{{f.EstadoFacturaId==1?'Pendiente':'Pagada'}}</td>
          <td>
            <button v-if="f.EstadoFacturaId==1" @click="pagar(f.Id, f.TotalAPagarFinal)">
              Pagar
            </button>
          </td>
        </tr>
      </tbody>
    </table>

    <p v-if="msg" style="color:green">{{msg}}</p>
    <p v-if="err" style="color:red">{{err}}</p>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue";
import api from "../axios";

const props = defineProps({ numeroFinca:String });

const numeroFinca = props.numeroFinca;
const propiedad = ref(null);
const ccs = ref([]);
const facturas = ref([]);
const msg = ref("");
const err = ref("");

const cargarTodo = async () => {
  msg.value = err.value = "";
  const det = await api.get(`/propiedades/${numeroFinca}`);
  propiedad.value = det.data.propiedad;
  ccs.value = det.data.conceptosCobro;

  const fac = await api.get(`/propiedades/${numeroFinca}/facturas`);
  facturas.value = fac.data;
};

const pagar = async (facturaId) => {
  try{
    msg.value = err.value = "";
    await api.post("/facturas/pagar", {
      facturaId,
      tipoMedioPagoId: 1, // por ahora fijo, luego lo haces dropdown
      numeroReferencia: "ADMIN-TEST",
      fechaPago: new Date().toISOString().slice(0,10),
    });
    msg.value = `Factura ${facturaId} pagada`;
    await cargarTodo(); // refrescar vista
  }catch(e){
    err.value = e.response?.data?.detail ?? "Error pagando";
  }
};

onMounted(cargarTodo);
</script>
