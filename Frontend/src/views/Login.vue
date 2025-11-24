<template>
  <div style="padding:2rem; max-width:400px;">
    <h2>Login Admin</h2>
    <input v-model="nombreUsuario" placeholder="Usuario" />
    <input v-model="contrasena" type="password" placeholder="Contraseña" />
    <button @click="login">Entrar</button>
    <p v-if="err" style="color:red">{{err}}</p>
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
    // guardalo simple en localStorage
    localStorage.setItem("admin", JSON.stringify(data));
    router.push("/propiedades");
  } catch (e) {
    err.value = e.response?.data?.detail ?? "Error login";
  }
};
</script>
