import { useEffect } from 'react';
import { useMap } from 'react-leaflet';

// Leaflet measures its container once, at init. If the container has not been
// laid out yet — which happens on first paint, inside a hidden tab, or behind a
// CSS grid that resolves late — it records a 0x0 viewport and every polygon
// projects to "M0 0". The map looks blank with no error in the console.
//
// invalidateSize() forces a re-measure. We run it on mount and then on every
// container resize, and re-fit the bounds afterwards because a zoom derived
// from a 0x0 viewport is meaningless.
export default function AutoFit({ bounds, padding = [10, 10] }) {
  const map = useMap();

  useEffect(() => {
    if (!map) return;

    const refit = () => {
      map.invalidateSize({ animate: false });
      if (bounds) map.fitBounds(bounds, { padding, animate: false });
    };

    // Synchronously first: by the time this effect runs the container is laid
    // out, and requestAnimationFrame does not fire in a backgrounded or
    // non-compositing tab, so it cannot be the only path.
    refit();

    // Then once more after the frame commits, to catch late layout (fonts,
    // grid resolution) that shifts the container after mount.
    const raf = requestAnimationFrame(refit);

    const container = map.getContainer();
    const observer = new ResizeObserver(refit);
    observer.observe(container);

    return () => {
      cancelAnimationFrame(raf);
      observer.disconnect();
    };
    // bounds is a fresh array each render; stringify to compare by value.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, JSON.stringify(bounds)]);

  return null;
}
