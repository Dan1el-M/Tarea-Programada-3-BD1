<template>
  <div style="padding:2rem;">
    <h2>Propiedades</h2>

    <input
      v-model="q"
      placeholder="Buscar finca o cédula"
      @input="cargar"
    />

    <table border="1" cellpadding="6" style="margin-top:1rem; width:100%;">
      <thead>
        <tr>
          <th>Finca</th>
          <th>Medidor</th>
          <th>Saldo m3</th>
          <th>Valor Fiscal</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="p in props"
          :key="p.NumeroFinca"
          @click="ver(p.NumeroFinca)"
          style="cursor:pointer;"
        >
          <td>{{ p.NumeroFinca }}</td>
          <td>{{ p.NumeroMedidor }}</td>
          <td>{{ p.SaldoM3 }}</td>
          <td>{{ p.ValorFiscal }}</td>
        </tr>

        <tr v-if="props.length === 0">
          <td colspan="4" style="text-align:center; padding:1rem;">
            No hay propiedades para mostrar
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue";
import api from "../axios";
import { useRouter } from "vue-router";

const router = useRouter();

const props = ref([]);
const q = ref("");

const cargar = async () => {
  try {
    const filtro = q.value.trim();

    // Si no hay filtro -> listar todo SIN mandar params
    let resp;
    if (filtro === "") {
      resp = await api.get("/propiedades");
    } else {
      resp = await api.get("/propiedades", { params: { q: filtro } });
    }

    props.value = resp.data;
  } catch (err) {
    console.error("Error cargando propiedades:", err);
    props.value = [];
  }
};

const ver = (numeroFinca) => router.push(`/propiedades/${numeroFinca}`);

onMounted(cargar);
</script>
