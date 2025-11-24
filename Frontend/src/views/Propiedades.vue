<template>
  <div class="page">
    <!-- Header simple -->
    <header class="topbar">
      <h1>Municipalidad – Pagos de Servicios</h1>
      <div class="user">
        <span>Admin</span>
        <button class="btn ghost" @click="logout">Salir</button>
      </div>
    </header>

    <!-- Buscador -->
    <section class="card">
      <h2>Buscar Propiedad</h2>

      <div class="toggle">
        <button
          class="toggle-btn"
          :class="{ active: modo === 'finca' }"
          @click="setModo('finca')"
        >
          Por Finca
        </button>
        <button
          class="toggle-btn"
          :class="{ active: modo === 'cedula' }"
          @click="setModo('cedula')"
        >
          Por Identificación
        </button>
      </div>

      <div class="search-row">
        <input
          v-model="q"
          :placeholder="modo === 'finca' ? 'Ej: F-0012' : 'Ej: 10000005'"
          @keyup.enter="buscar"
        />
        <button class="btn primary" @click="buscar">Buscar</button>
        <button v-if="q" class="btn" @click="limpiar">Limpiar</button>
      </div>
    </section>

    <!-- Lista de propiedades (si hay resultados) -->
    <section class="card">
      <h3 v-if="modo === 'cedula' && q">Propiedades del propietario</h3>
      <h3 v-else>Propiedades</h3>

      <table class="table">
        <thead>
          <tr>
            <th>Finca</th>
            <th>Medidor</th>
            <th>Saldo m³</th>
            <th>Valor Fiscal</th>
            <th>Acción</th>
          </tr>
        </thead>

        <tbody>
          <tr v-for="p in props" :key="p.NumeroFinca">
            <td>{{ p.NumeroFinca }}</td>
            <td>{{ p.NumeroMedidor }}</td>
            <td>{{ p.SaldoM3 }}</td>
            <td>{{ fmtCRC(p.ValorFiscal) }}</td>
            <td>
              <button class="btn primary" @click="verEstado(p.NumeroFinca)">
                Ver estado
              </button>
            </td>
          </tr>

          <tr v-if="props.length === 0">
            <td colspan="5" class="empty">No hay propiedades para mostrar</td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="msg" class="toast">{{ msg }}</div>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue";
import { useRouter } from "vue-router";
import api from "../axios";

const router = useRouter();

const modo = ref("finca"); // finca | cedula
const q = ref("");
const props = ref([]);
const msg = ref("");

const fmtCRC = (n) => {
  if (n == null) return "-";
  return new Intl.NumberFormat("es-CR", {
    style: "currency",
    currency: "CRC",
    maximumFractionDigits: 0,
  }).format(Number(n));
};

const cargarTodo = async () => {
  try {
    const resp = await api.get("/propiedades");
    props.value = resp.data ?? [];
  } catch (e) {
    props.value = [];
  }
};

const buscar = async () => {
  msg.value = "";
  const filtro = q.value.trim();

  try {
    if (!filtro) {
      // si no hay texto, vuelve a listar todo
      await cargarTodo();
      return;
    }

    const resp = await api.get("/propiedades", { params: { q: filtro } });
    props.value = resp.data ?? [];

    if (!props.value.length) msg.value = "No se encontraron propiedades.";
  } catch (e) {
    props.value = [];
    msg.value = "Error buscando propiedades.";
  }
};

const limpiar = async () => {
  q.value = "";
  msg.value = "";
  await cargarTodo();
};

const setModo = async (m) => {
  modo.value = m;
  await limpiar();
};

// redirigir a otra vista
const verEstado = (numeroFinca) => {
  router.push(`/propiedades/${numeroFinca}`);
};

const logout = () => {
  router.push("/login");
};

onMounted(cargarTodo);
</script>

<style scoped>
.page { padding: 1.2rem; background: #f5f6f8; min-height: 100vh; font-family: system-ui; }
.topbar {
  background: white; padding: .9rem 1.2rem; border-radius: 12px;
  display: flex; justify-content: space-between; align-items: center;
  box-shadow: 0 2px 8px rgba(0,0,0,.06); margin-bottom: 1rem;
}
.user { display: flex; gap: .6rem; align-items: center; }

.card {
  background: white; padding: 1rem 1.2rem; border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,.06); margin-bottom: 1rem;
}

.toggle {
  display: inline-flex; background: #eef0f3; border-radius: 10px;
  padding: 4px; gap: 4px; margin: .6rem 0 1rem;
}
.toggle-btn {
  border: none; padding: .45rem .9rem; background: transparent;
  cursor: pointer; border-radius: 8px; font-weight: 600; color: #444;
}
.toggle-btn.active { background: white; box-shadow: 0 1px 4px rgba(0,0,0,.12); }

.search-row { display: flex; gap: .6rem; align-items: center; }
.search-row input {
  flex: 1; padding: .6rem .7rem; border: 1px solid #d7d9dd;
  border-radius: 8px; outline: none;
}

.btn {
  padding: .55rem .9rem; border: 1px solid #cfd2d8;
  background: white; border-radius: 8px; cursor: pointer; font-weight: 600;
}
.btn.primary { background: #1f6feb; color: white; border-color: #1f6feb; }
.btn.ghost { background: transparent; }

.hint { color:#666; margin-top:.5rem; }

.table { width: 100%; border-collapse: collapse; margin-top: .6rem; }
.table th, .table td { border-bottom: 1px solid #eef0f3; padding: .6rem .5rem; text-align: left; }
.empty { text-align: center; padding: 1rem; color: #777; }

.toast {
  position: fixed; bottom: 18px; right: 18px;
  background: #111827; color: white; padding: .7rem 1rem;
  border-radius: 10px; box-shadow: 0 6px 20px rgba(0,0,0,.25);
}
</style>
