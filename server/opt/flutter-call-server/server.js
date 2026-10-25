const http = require("node:http");
const { Server } = require("socket.io");

const server = http.createServer();

const io = new Server(server, {
  transports: ["websocket", "polling"],
  maxHttpBufferSize: 100000,
});

const users = new Map();
const allowedUsers = new Set(["user-a", "user-b"]);

io.use((socket, next) => {
  const { userId, token } = socket.handshake.auth;

  if (
    !allowedUsers.has(userId) ||
    !process.env.DEMO_TOKEN ||
    token !== process.env.DEMO_TOKEN
  ) {
    return next(new Error("Unauthorized"));
  }

  next();
});

io.on("connection", (socket) => {
  const userId = socket.handshake.auth.userId;

  // 同じユーザーIDの重複接続は拒否
  if (users.has(userId)) {
    socket.emit("server:error", "Already connected");
    socket.disconnect(true);
    return;
  }

  users.set(userId, socket.id);
  console.log("Connected:", userId);

  socket.emit("server:ready", { userId });

  const events = [
    "call:invite",
    "call:accept",
    "call:reject",
    "call:offer",
    "call:answer",
    "call:ice",
    "call:hangup",
  ];

  for (const event of events) {
    socket.on(event, (data) => {
      if (!data || typeof data !== "object") return;

      const { to, ...payload } = data;

      if (!allowedUsers.has(to) || to === userId) return;

      const targetSocketId = users.get(to);

      if (!targetSocketId) {
        socket.emit("call:unavailable", { to });
        return;
      }

      io.to(targetSocketId).emit(event, {
        from: userId,
        ...payload,
      });
    });
  }

  socket.on("disconnect", () => {
    if (users.get(userId) === socket.id) {
      users.delete(userId);
    }

    const peer = userId === "user-a" ? "user-b" : "user-a";
    const targetSocketId = users.get(peer);

    if (targetSocketId) {
      io.to(targetSocketId).emit("call:hangup", {
        from: userId,
        reason: "disconnected",
      });
    }

    console.log("Disconnected:", userId);
  });
});

server.listen(3000, "127.0.0.1", () => {
  console.log("Socket.IO listening on 127.0.0.1:3000");
});
