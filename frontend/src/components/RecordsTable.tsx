import type { PipelineRecord } from "@/api/types";
import {
  formatBounds,
  formatDiameter,
  formatExtent,
  formatMetres,
  formatNumber,
} from "@/lib/format";

interface RecordsTableProps {
  records: PipelineRecord[];
  total: number;
  offset: number;
  pageSize: number;
  isLoading: boolean;
  onOffsetChange: (offset: number) => void;
}

export function RecordsTable({
  records,
  total,
  offset,
  pageSize,
  isLoading,
  onOffsetChange,
}: RecordsTableProps) {
  const from = total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + pageSize, total);
  const hasPrevious = offset > 0;
  const hasNext = to < total;

  return (
    <section className="panel" aria-labelledby="output-heading">
      <header className="panel__header">
        <div className="panel__title">
          <h2 id="output-heading">Output</h2>
          <p className="panel__subtitle">Current state of each surviving object</p>
        </div>
        {total > 0 && (
          <span className="panel__count">
            {from}–{to} of {total}
          </span>
        )}
      </header>

      {isLoading && records.length === 0 ? (
        <ul className="skeleton-list" aria-hidden="true">
          {[0, 1, 2, 3].map((row) => (
            <li key={row} className="skeleton" />
          ))}
        </ul>
      ) : records.length === 0 ? (
        <p className="muted">This run produced no records.</p>
      ) : (
        <>
          {/*
            One DOM, two presentations: below the breakpoint CSS restacks each row into
            a card, using data-label for the field names. Keeps table semantics correct
            at every width with no duplicated markup.
          */}
          <div className="table-wrap" data-loading={isLoading ? "true" : undefined}>
            <table className="table table--stacking">
              <thead>
                <tr>
                  <th scope="col">Object</th>
                  <th scope="col">Type</th>
                  <th scope="col" className="numeric">
                    Diameter
                  </th>
                  <th scope="col" className="numeric">
                    Vertices
                  </th>
                  <th scope="col" className="numeric">
                    Segments
                  </th>
                  <th scope="col" className="numeric">
                    Length
                  </th>
                  <th scope="col" className="numeric">
                    Extent
                  </th>
                </tr>
              </thead>
              <tbody>
                {records.map((record) => (
                  <tr key={record.object_id}>
                    <td data-label="Object">
                      <span className="mono cell-id" title={record.object_id}>
                        {record.object_id.slice(-12)}
                      </span>
                      <span className="cell-sub mono" title={record.geometry}>
                        {record.geometry.split(" (")[0]}
                      </span>
                    </td>
                    <td data-label="Type">{record.type ?? "—"}</td>
                    <td data-label="Diameter" className="numeric">
                      {formatDiameter(record.diameter)}
                    </td>
                    <td data-label="Vertices" className="numeric">
                      {formatNumber(record.vertex_count)}
                    </td>
                    <td data-label="Segments" className="numeric">
                      {formatNumber(record.segment_count)}
                    </td>
                    <td data-label="Length" className="numeric">
                      {formatMetres(record.length_m)}
                    </td>
                    <td data-label="Extent" className="numeric" title={formatBounds(record.bbox)}>
                      {formatExtent(record.bbox)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {(hasPrevious || hasNext) && (
            <nav className="pager" aria-label="Output pages">
              <button
                type="button"
                className="button button--ghost"
                onClick={() => {
                  onOffsetChange(offset - pageSize);
                }}
                disabled={!hasPrevious || isLoading}
              >
                ← Previous
              </button>
              <span className="pager__status" aria-live="polite">
                {from}–{to} of {total}
              </span>
              <button
                type="button"
                className="button button--ghost"
                onClick={() => {
                  onOffsetChange(offset + pageSize);
                }}
                disabled={!hasNext || isLoading}
              >
                Next →
              </button>
            </nav>
          )}
        </>
      )}
    </section>
  );
}
