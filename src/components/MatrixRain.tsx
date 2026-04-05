"use client";

import { useEffect, useRef } from "react";

export default function MatrixRain() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animId: number;
    let columns: number[] = [];

    const CHARS =
      "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789ABCDEF";
    const FONT_SIZE = 14;
    const DROP_SPEED = 0.3;

    function resize() {
      canvas!.width = window.innerWidth;
      canvas!.height = window.innerHeight;
      const colCount = Math.floor(canvas!.width / FONT_SIZE);
      columns = Array.from({ length: colCount }, () =>
        Math.random() * -canvas!.height / FONT_SIZE
      );
    }

    function draw() {
      // Semi-transparent black overlay creates trail effect
      ctx!.fillStyle = "rgba(0, 2, 0, 0.04)";
      ctx!.fillRect(0, 0, canvas!.width, canvas!.height);

      ctx!.font = `${FONT_SIZE}px monospace`;

      for (let i = 0; i < columns.length; i++) {
        const char = CHARS[Math.floor(Math.random() * CHARS.length)];
        const x = i * FONT_SIZE;
        const y = columns[i] * FONT_SIZE;

        // Lead character is bright white-green
        if (y > 0) {
          ctx!.fillStyle = "rgba(180, 255, 180, 0.9)";
          ctx!.fillText(char, x, y);

          // Trail characters are dimmer green
          if (y > FONT_SIZE) {
            ctx!.fillStyle = "rgba(0, 200, 65, 0.15)";
            ctx!.fillText(
              CHARS[Math.floor(Math.random() * CHARS.length)],
              x,
              y - FONT_SIZE
            );
          }
        }

        columns[i] += DROP_SPEED;

        // Reset column randomly when it reaches bottom
        if (columns[i] * FONT_SIZE > canvas!.height && Math.random() > 0.985) {
          columns[i] = Math.random() * -20;
        }
      }

      animId = requestAnimationFrame(draw);
    }

    resize();
    draw();
    window.addEventListener("resize", resize);

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("resize", resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        width: "100vw",
        height: "100vh",
        zIndex: 0,
        pointerEvents: "none",
        opacity: 0.35,
      }}
    />
  );
}
