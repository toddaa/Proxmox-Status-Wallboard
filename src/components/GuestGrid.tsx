"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import type { GuestData } from "@/types/proxmox";
import GuestCard from "./GuestCard";

interface GuestGridProps {
  guests: GuestData[];
  visibleCount?: number;
  rotateInterval?: number; // seconds
}

export default function GuestGrid({
  guests,
  visibleCount = 3,
  rotateInterval = 8,
}: GuestGridProps) {
  const [offset, setOffset] = useState(0);
  const [isSliding, setIsSliding] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);

  const canRotate = guests.length > visibleCount;

  const rotateOne = useCallback(() => {
    if (!canRotate) return;
    setIsSliding(true);
    // After transition ends, jump offset forward and reset transform
    setTimeout(() => {
      setOffset((prev) => (prev + 1) % guests.length);
      setIsSliding(false);
    }, 500);
  }, [canRotate, guests.length]);

  useEffect(() => {
    if (!canRotate) return;
    const timer = setInterval(rotateOne, rotateInterval * 1000);
    return () => clearInterval(timer);
  }, [rotateOne, rotateInterval, canRotate]);

  // Reset offset if guest list changes
  useEffect(() => {
    setOffset(0);
    setIsSliding(false);
  }, [guests.length]);

  // Build the visible cards (visibleCount + 1 for the incoming card during slide)
  const displayCount = canRotate ? visibleCount + 1 : guests.length;
  const displayGuests: GuestData[] = [];
  for (let i = 0; i < displayCount && i < guests.length; i++) {
    displayGuests.push(guests[(offset + i) % guests.length]);
  }

  return (
    <div className="guest-section">
      <div className="guest-header">
        <div className="guest-title">Virtual Machines & Containers</div>
        {canRotate && (
          <div className="guest-count font-mono">
            {guests.length} guests
          </div>
        )}
      </div>

      <div className="guest-grid-wrapper">
        <div
          ref={trackRef}
          className="guest-track"
          style={{
            transform: isSliding
              ? `translateX(calc(-1 * (100% / ${visibleCount} + 14px / ${visibleCount})))`
              : "translateX(0)",
            transition: isSliding
              ? "transform 0.5s ease-in-out"
              : "none",
          }}
        >
          {displayGuests.length === 0 ? (
            <div className="no-guests font-mono">No guests found</div>
          ) : (
            displayGuests.map((g, i) => (
              <GuestCard key={`${g.vmid}-${(offset + i) % guests.length}`} guest={g} />
            ))
          )}
        </div>
      </div>
    </div>
  );
}
