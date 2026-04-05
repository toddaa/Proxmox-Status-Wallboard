"use client";

import { useState, useEffect } from "react";

export default function Clock() {
  const [time, setTime] = useState("--:--:--");

  useEffect(() => {
    function tick() {
      setTime(
        new Date().toLocaleTimeString("en-US", {
          hour12: false,
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
        })
      );
    }
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, []);

  return <div className="clock font-mono">{time}</div>;
}
