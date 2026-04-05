import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import RingGauge from "./RingGauge";

describe("RingGauge", () => {
  it("renders value and unit labels", () => {
    render(<RingGauge percent={42} color="#0f0" value="42" unit="%" />);
    expect(screen.getByText("42")).toBeInTheDocument();
    expect(screen.getByText("%")).toBeInTheDocument();
  });

  it("clamps percent to 0..100 for the dash offset", () => {
    const { container } = render(
      <RingGauge percent={150} color="#0f0" value="150" unit="%" />
    );
    // Second circle is the progress arc
    const circles = container.querySelectorAll("circle");
    const progress = circles[1];
    // At 100% the offset should be 0
    expect(progress.getAttribute("stroke-dashoffset")).toBe("0");
  });

  it("treats negative percent as zero", () => {
    const { container } = render(
      <RingGauge percent={-10} color="#0f0" value="0" unit="%" />
    );
    const circles = container.querySelectorAll("circle");
    const progress = circles[1];
    const dasharray = parseFloat(progress.getAttribute("stroke-dasharray") || "0");
    const dashoffset = parseFloat(progress.getAttribute("stroke-dashoffset") || "0");
    // At 0% the offset equals the full circumference
    expect(dashoffset).toBeCloseTo(dasharray);
  });
});
