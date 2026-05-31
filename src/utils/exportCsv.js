export function exportToCsv(rows, filename, columns) {
  if (!rows || rows.length === 0) return;
  const keys = columns || Object.keys(rows[0]);
  const escape = (val) => { if (val == null) return ""; const str = Array.isArray(val) ? val.join("; ") : String(val); return str.includes(",") || str.includes('"') || str.includes("\n") ? `"${str.replace(/"/g, '""')}"` : str; };
  const csv = `${keys.map(escape).join(",")}\n${rows.map(row => keys.map(k => escape(row[k])).join(",")).join("\n")}`;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob); const a = document.createElement("a"); a.href = url; a.download = `${filename}.csv`; a.click(); URL.revokeObjectURL(url);
}