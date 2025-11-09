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
