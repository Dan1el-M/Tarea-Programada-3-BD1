/*
import { createRouter, createWebHistory } from "vue-router";
import Portada from "./views/portadaPrueba.vue";

const routes = [
  { path: "/", redirect: "/portadaPrueba" },
  { path: "/portadaPrueba", component: Portada },
];

export default createRouter({
  history: createWebHistory(),
  routes,
});
*/
import { createRouter, createWebHistory } from "vue-router";
import Login from "./views/Login.vue";
import Propiedades from "./views/Propiedades.vue";
import PropiedadDetalle from "./views/PropiedadDetalle.vue";

const routes = [
  { path: "/", redirect: "/login" },
  { path: "/login", component: Login },
  { path: "/propiedades", component: Propiedades },
  { path: "/propiedades/:numeroFinca", component: PropiedadDetalle, props:true },
];

export default createRouter({ history: createWebHistory(), routes });
