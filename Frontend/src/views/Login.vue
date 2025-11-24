<template>
  <div class="login-container">
    <div class="login-card">
      <h2 class="login-title">Ingresar al Sistema</h2>

      <div class="input-group">
        <label>Usuario</label>
        <input v-model="nombreUsuario" type="text" placeholder="Ej: admin01" />
      </div>

      <div class="input-group">
        <label>Contraseña</label>
        <input v-model="contrasena" type="password" placeholder="••••••••" />
      </div>

      <button class="login-btn" @click="login">Entrar</button>

      <p v-if="err" class="error-msg">{{ err }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue";
import api from "../axios";
import { useRouter } from "vue-router";

const router = useRouter();
const nombreUsuario = ref("");
const contrasena = ref("");
const err = ref("");

const login = async () => {
  try {
    err.value = "";
    const { data } = await api.post("/login", {
      nombreUsuario: nombreUsuario.value,
      contrasena: contrasena.value,
    });
    localStorage.setItem("admin", JSON.stringify(data));
    router.push("/propiedades");
  } catch (e) {
    err.value = e.response?.data?.detail ?? "Error de inicio de sesión";
  }
};
</script>

<style scoped>
/* Centrado completo */
.login-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
  background: #f4f6f8;
  padding: 1rem;
}

/* Tarjeta del login */
.login-card {
  background: white;
  width: 100%;
  max-width: 420px;
  padding: 2rem 2.5rem;
  border-radius: 14px;
  box-shadow: 0px 4px 18px rgba(0, 0, 0, 0.08);
}

/* Título */
.login-title {
  font-size: 1.6rem;
  font-weight: 700;
  margin-bottom: 1.5rem;
  text-align: center;
}

/* Label + Input */
.input-group {
  margin-bottom: 1rem;
}

.input-group label {
  font-weight: 600;
  font-size: 0.9rem;
  display: block;
  margin-bottom: 0.3rem;
}

.input-group input {
  width: 100%;
  padding: 0.7rem;
  border-radius: 8px;
  border: 1px solid #d1d5db;
  font-size: 1rem;
  transition: 0.2s;
}

.input-group input:focus {
  outline: none;
  border-color: #2563eb;
  box-shadow: 0 0 4px rgba(37, 99, 235, 0.3);
}

/* Botón */
.login-btn {
  width: 100%;
  background: #2563eb;
  border: none;
  padding: 0.8rem;
  color: white;
  font-size: 1.05rem;
  font-weight: 600;
  border-radius: 8px;
  cursor: pointer;
  margin-top: 0.5rem;
  transition: 0.2s;
}

.login-btn:hover {
  background: #1d4ed8;
}

/* Error */
.error-msg {
  margin-top: 1rem;
  text-align: center;
  color: #dc2626;
  font-weight: 600;
}
</style>
