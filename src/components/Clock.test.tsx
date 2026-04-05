import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import Clock from "./Clock";

describe("Clock", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-05T12:34:56"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("renders the current time in HH:MM:SS format", () => {
    render(<Clock />);
    expect(screen.getByText(/12:34:56/)).toBeInTheDocument();
  });

  it("updates every second", () => {
    render(<Clock />);
    expect(screen.getByText(/12:34:56/)).toBeInTheDocument();

    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(screen.getByText(/12:34:57/)).toBeInTheDocument();
  });
});
