export const socketConfig = {
  url: import.meta.env.VITE_SOCKET_URL,
  reconnectionAttempts: Infinity,
  reconnectionDelay: 500,
  reconnectionDelayMax: 5000,
};
