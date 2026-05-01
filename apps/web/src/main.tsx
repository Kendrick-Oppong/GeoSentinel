import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "sonner";
import App from "./App";
import "./index.css";

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
      <Toaster
        position="top-right"
        icons={{
          success: null,
          error: null,
          info: null,
          warning: null,
          loading: null,
        }}
        closeButton
        richColors
        toastOptions={{
          duration: 5000,
          className:
            "rounded-lg !border !border-border !bg-card !text-foreground !shadow-card !font-sans",
          style: {
            fontFamily: "var(--font-sans)",
            background: "var(--card)",
            color: "var(--foreground)",
            borderColor: "var(--border)",
            boxShadow: "var(--shadow-card)",
          },
          classNames: {
            toast: "group", // Ensure 'group' is on the base toast
            success: "!bg-card !border-live/20",
            error: "!bg-card !border-danger/20",
            // Use global title/description keys to handle specific variant colors
            title:
              "font-semibold group-data-[type=success]:!text-live group-data-[type=error]:!text-danger",
            description:
              "group-data-[type=success]:!text-live/80 group-data-[type=error]:!text-danger/80",
          },
        }}
      />
    </QueryClientProvider>
  </React.StrictMode>,
);
