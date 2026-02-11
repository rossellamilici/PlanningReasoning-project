#!/usr/bin/env python3
"""
Cyber-Defense Orchestrator - GUI
================================
TCP server on port 9999.
- Prolog connects as client.
- Buttons send exogenous actions (one line per command).
- Receives status updates from Prolog (format: "node:status").

Usage:
  1. Start this GUI first:   python3 gui.py
  2. Then start Prolog:      swipl -g main main.pl
"""

import tkinter as tk
import socket
import threading
import queue
import time
import platform

# ==============================================================================
# NETWORK CONFIG
# ==============================================================================
HOST = "0.0.0.0"
PORT = 9999

# ==============================================================================
# DOMAIN DATA (must match domain.pl)
# ==============================================================================
NODES = ["db_server", "web_server_1", "web_server_2", "workstation_a"]
SUBNETS = ["subnet_alpha", "subnet_beta"]

# ==============================================================================
# HIGH CONTRAST COLOR SCHEME (dark bg, bright elements)
# ==============================================================================
BG_DARK      = "#0a0a1a"
BG_CARD      = "#1a1a3e"
BORDER       = "#333366"

TEXT_WHITE   = "#ffffff"
TEXT_DIM     = "#8888bb"
TEXT_CYAN    = "#55ddff"

# Status colors - very bright on dark background
STATUS = {
    "clean":     "#00ff88",
    "infected":  "#ff2244",
    "isolated":  "#ffbb00",
    "patching":  "#44aaff",
    "restoring": "#cc66ff",
    "unknown":   "#666688",
}
SUBNET_STATUS = {
    "online":  "#00ff88",
    "down":    "#ff2244",
    "unknown": "#666688",
}

IS_MAC = platform.system() == "Darwin"
FONT = "Menlo" if IS_MAC else "Consolas"


def make_button(parent, text, bg_color, command):
    """
    Create a clearly visible button on ANY OS.
    macOS ignores tk.Button bg/fg, so we use Frame+Label with bindings.
    """
    frame = tk.Frame(parent, bg=bg_color, cursor="hand2")

    # Darken color for border effect
    label = tk.Label(frame, text=text,
                     font=(FONT, 11, "bold"),
                     fg="#ffffff", bg=bg_color,
                     padx=14, pady=10, cursor="hand2")
    label.pack(fill="both", expand=True, padx=2, pady=2)

    # Hover: lighten
    def on_enter(e):
        # Lighten by blending toward white
        r = min(255, int(bg_color[1:3], 16) + 40)
        g = min(255, int(bg_color[3:5], 16) + 40)
        b = min(255, int(bg_color[5:7], 16) + 40)
        lighter = f"#{r:02x}{g:02x}{b:02x}"
        frame.configure(bg=lighter)
        label.configure(bg=lighter)

    def on_leave(e):
        frame.configure(bg=bg_color)
        label.configure(bg=bg_color)

    def on_click(e):
        command()

    for w in (frame, label):
        w.bind("<Button-1>", on_click)
        w.bind("<Enter>", on_enter)
        w.bind("<Leave>", on_leave)

    return frame


class CyberDefenseGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Cyber-Defense Orchestrator")
        self.root.geometry("820x740")
        self.root.configure(bg=BG_DARK)
        self.root.resizable(False, False)

        self.client_socket = None
        self.client_lock = threading.Lock()
        self.msg_queue = queue.Queue()
        self.log_queue = queue.Queue()
        self.running = True

        self.node_states = {n: "clean" for n in NODES}
        self.subnet_states = {s: "online" for s in SUBNETS}
        self.node_indicators = {}
        self.subnet_indicators = {}

        self._build_ui()
        self._start_server()
        self._poll_queues()

    # ==========================================================================
    # BUILD UI
    # ==========================================================================
    def _build_ui(self):
        # ---- TITLE ----
        tk.Label(self.root,
                 text="CYBER-DEFENSE ORCHESTRATOR",
                 font=(FONT, 20, "bold"),
                 fg=TEXT_CYAN, bg=BG_DARK).pack(pady=(14, 2))

        self.conn_label = tk.Label(self.root,
                                   text="⏳  Waiting for Prolog...",
                                   font=(FONT, 11),
                                   fg="#ffbb00", bg=BG_DARK)
        self.conn_label.pack(pady=(0, 6))

        self._sep()

        # ---- NETWORK STATUS ----
        tk.Label(self.root, text="NETWORK STATUS",
                 font=(FONT, 13, "bold"),
                 fg=TEXT_CYAN, bg=BG_DARK).pack(anchor="w", padx=24, pady=(4, 8))

        # Nodes
        nodes_row = tk.Frame(self.root, bg=BG_DARK)
        nodes_row.pack(fill="x", padx=20, pady=(0, 6))

        for node in NODES:
            card = tk.Frame(nodes_row, bg=BG_CARD,
                            highlightbackground=BORDER, highlightthickness=1)
            card.pack(side="left", expand=True, fill="x", padx=4, ipady=6)

            name = node.replace("_", " ").upper()
            tk.Label(card, text=name,
                     font=(FONT, 9, "bold"),
                     fg=TEXT_WHITE, bg=BG_CARD).pack(pady=(6, 0))

            ind = tk.Label(card, text="●  CLEAN",
                           font=(FONT, 13, "bold"),
                           fg=STATUS["clean"], bg=BG_CARD)
            ind.pack(pady=(2, 6))
            self.node_indicators[node] = ind

        # Subnets
        sub_row = tk.Frame(self.root, bg=BG_DARK)
        sub_row.pack(fill="x", padx=20)

        for subnet in SUBNETS:
            card = tk.Frame(sub_row, bg=BG_CARD,
                            highlightbackground=BORDER, highlightthickness=1)
            card.pack(side="left", expand=True, fill="x", padx=4, ipady=6)

            name = subnet.replace("_", " ").upper()
            tk.Label(card, text=name,
                     font=(FONT, 9, "bold"),
                     fg=TEXT_WHITE, bg=BG_CARD).pack(pady=(6, 0))

            ind = tk.Label(card, text="●  ONLINE",
                           font=(FONT, 13, "bold"),
                           fg=SUBNET_STATUS["online"], bg=BG_CARD)
            ind.pack(pady=(2, 6))
            self.subnet_indicators[subnet] = ind

        self._sep()

        # ---- TRIGGER EVENTS ----
        tk.Label(self.root, text="TRIGGER EXOGENOUS EVENTS",
                 font=(FONT, 13, "bold"),
                 fg="#ffbb00", bg=BG_DARK).pack(anchor="w", padx=24, pady=(4, 8))

        # Intrusion buttons
        tk.Label(self.root, text="🔴  INTRUSION ALERT",
                 font=(FONT, 11, "bold"),
                 fg="#ff6666", bg=BG_DARK).pack(anchor="w", padx=28)

        intr_row = tk.Frame(self.root, bg=BG_DARK)
        intr_row.pack(fill="x", padx=24, pady=(4, 10))
        for node in NODES:
            btn = make_button(intr_row,
                              text=f"⚠  {node}",
                              bg_color="#aa0020",
                              command=lambda n=node: self._send_event(
                                  f"alert_intrusion({n})"))
            btn.pack(side="left", expand=True, fill="x", padx=3)

        # Crash buttons
        tk.Label(self.root, text="⚡  SERVICE CRASH",
                 font=(FONT, 11, "bold"),
                 fg="#ffaa44", bg=BG_DARK).pack(anchor="w", padx=28)

        crash_row = tk.Frame(self.root, bg=BG_DARK)
        crash_row.pack(fill="x", padx=24, pady=(4, 10))
        for subnet in SUBNETS:
            btn = make_button(crash_row,
                              text=f"💥  {subnet}",
                              bg_color="#aa5500",
                              command=lambda s=subnet: self._send_event(
                                  f"service_crash({s})"))
            btn.pack(side="left", expand=True, fill="x", padx=3)

        # Reset button
        reset_row = tk.Frame(self.root, bg=BG_DARK)
        reset_row.pack(fill="x", padx=24, pady=(0, 4))
        btn = make_button(reset_row,
                          text="🔄  NETWORK RESET",
                          bg_color="#0044aa",
                          command=lambda: self._send_event("network_reset"))
        btn.pack(fill="x", padx=3)

        self._sep()

        # ---- EVENT LOG ----
        tk.Label(self.root, text="EVENT LOG",
                 font=(FONT, 10, "bold"),
                 fg=TEXT_DIM, bg=BG_DARK).pack(anchor="w", padx=24, pady=(4, 4))

        log_frame = tk.Frame(self.root, bg=BORDER)
        log_frame.pack(fill="both", expand=True, padx=24, pady=(0, 14))

        self.log_text = tk.Text(log_frame, height=7,
                                font=(FONT, 10),
                                bg="#050510", fg="#99aacc",
                                insertbackground="white",
                                selectbackground="#333366",
                                relief="flat", state="disabled",
                                wrap="word", padx=8, pady=6)
        self.log_text.pack(fill="both", expand=True, padx=1, pady=1)

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _sep(self):
        tk.Frame(self.root, bg=BORDER, height=1).pack(fill="x", padx=20, pady=6)

    # ==========================================================================
    # TCP SERVER
    # ==========================================================================
    def _start_server(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((HOST, PORT))
        self.server_socket.listen(1)
        self.server_socket.settimeout(1.0)
        self._log(f"Server listening on port {PORT}...")

        t = threading.Thread(target=self._accept_loop, daemon=True)
        t.start()

    def _accept_loop(self):
        while self.running:
            try:
                client, addr = self.server_socket.accept()
                with self.client_lock:
                    if self.client_socket:
                        try: self.client_socket.close()
                        except: pass
                    self.client_socket = client
                    self.client_socket.settimeout(0.5)

                self.msg_queue.put(("connected", None))
                self._log(f"Prolog connected from {addr}")

                t = threading.Thread(target=self._read_loop,
                                     args=(client,), daemon=True)
                t.start()

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self._log(f"Accept error: {e}")
                break

    def _read_loop(self, sock):
        buffer = ""
        while self.running:
            try:
                data = sock.recv(4096)
                if not data:
                    self._log("Prolog disconnected")
                    self.msg_queue.put(("disconnected", None))
                    break
                buffer += data.decode("utf-8", errors="replace")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if ":" in line:
                        target, status = line.split(":", 1)
                        self.msg_queue.put(("status",
                                            (target.strip(), status.strip())))
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self._log(f"Read error: {e}")
                    self.msg_queue.put(("disconnected", None))
                break

    # ==========================================================================
    # SEND EVENTS
    # ==========================================================================
    def _send_event(self, cmd):
        with self.client_lock:
            if not self.client_socket:
                self._log("⛔ Cannot send: Prolog not connected!")
                return
            try:
                self.client_socket.sendall((cmd + "\n").encode("utf-8"))
                self._log(f"SENT → {cmd}")
            except Exception as e:
                self._log(f"Send error: {e}")

    # ==========================================================================
    # UI UPDATE LOOP
    # ==========================================================================
    def _poll_queues(self):
        while not self.msg_queue.empty():
            msg_type, data = self.msg_queue.get_nowait()
            if msg_type == "connected":
                self.conn_label.config(text="✅  Prolog connected", fg="#00ff88")
            elif msg_type == "disconnected":
                self.conn_label.config(text="❌  Prolog disconnected", fg="#ff2244")
                with self.client_lock:
                    self.client_socket = None
            elif msg_type == "status":
                target, status = data
                self._update_status(target, status)

        while not self.log_queue.empty():
            text = self.log_queue.get_nowait()
            self.log_text.config(state="normal")
            self.log_text.insert("end", text + "\n")
            self.log_text.see("end")
            self.log_text.config(state="disabled")

        if self.running:
            self.root.after(100, self._poll_queues)

    def _update_status(self, target, status):
        if target in self.node_indicators:
            self.node_states[target] = status
            color = STATUS.get(status, STATUS["unknown"])
            self.node_indicators[target].config(
                text=f"●  {status.upper()}", fg=color)
            self._log(f"← {target}: {status}")

        elif target in self.subnet_indicators:
            self.subnet_states[target] = status
            color = SUBNET_STATUS.get(status, SUBNET_STATUS["unknown"])
            self.subnet_indicators[target].config(
                text=f"●  {status.upper()}", fg=color)
            self._log(f"← {target}: {status}")

    def _log(self, text):
        ts = time.strftime("%H:%M:%S")
        self.log_queue.put(f"[{ts}] {text}")

    def _on_close(self):
        self.running = False
        with self.client_lock:
            if self.client_socket:
                try: self.client_socket.close()
                except: pass
        try: self.server_socket.close()
        except: pass
        self.root.destroy()


# ==============================================================================
if __name__ == "__main__":
    root = tk.Tk()
    app = CyberDefenseGUI(root)
    root.mainloop()
