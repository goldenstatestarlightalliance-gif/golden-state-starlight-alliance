import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Page not found</h1>
        <p className="lede">
          That page does not exist. If you were looking for a county, it is
          reachable from the progress map.
        </p>
      </header>
      <p>
        <Link className="btn btn-primary" to="/map">Go to the progress map</Link>
      </p>
    </div>
  );
}
