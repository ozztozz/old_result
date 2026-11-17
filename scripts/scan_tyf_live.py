import argparse
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
from requests.adapters import HTTPAdapter

BASE_URL = "https://canli.tyf.gov.tr/live/2026/{item_id}/"
DEFAULT_START = 1005900
DEFAULT_END = 1005950
DEFAULT_WORKERS = 15
DEFAULT_TIMEOUT = 5.0
DEFAULT_OUTPUT = "tyf_status_200.txt"

print_lock = threading.Lock()


def create_session(pool_size: int) -> requests.Session:
    session = requests.Session()
    adapter = HTTPAdapter(pool_connections=pool_size, pool_maxsize=pool_size)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })
    return session


def check_id(session: requests.Session, item_id: int, timeout: float) -> tuple[int, str, int | None]:
    url = BASE_URL.format(item_id=item_id)
    try:
        # stream=True: sadece status/header kontrolü için gövdeyi indirmeden kapatır
        with session.get(url, timeout=timeout, stream=True, allow_redirects=True) as resp:
            return item_id, url, resp.status_code
    except requests.RequestException:
        return item_id, url, None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="canli.tyf.gov.tr/live/2026/<id>/ adresinde status 200 dönen ID'leri tarar."
    )
    parser.add_argument("--start", type=int, default=DEFAULT_START, help=f"Başlangıç ID (varsayılan: {DEFAULT_START})")
    parser.add_argument("--end", type=int, default=DEFAULT_END, help=f"Bitiş ID (varsayılan: {DEFAULT_END})")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS, help=f"Eşzamanlı istek sayısı (varsayılan: {DEFAULT_WORKERS})")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help=f"İstek zaman aşımı sn (varsayılan: {DEFAULT_TIMEOUT})")
    parser.add_argument("--output", type=str, default=DEFAULT_OUTPUT, help=f"200 dönenlerin kaydedileceği dosya (varsayılan: {DEFAULT_OUTPUT})")
    args = parser.parse_args()

    if args.start > args.end:
        raise ValueError(f"Başlangıç ({args.start}) bitişten ({args.end}) büyük olamaz.")

    total = args.end - args.start + 1
    print(f"Tarama başlıyor: {args.start} -> {args.end} (Toplam: {total} istek, Worker: {args.workers})")
    print(f"Status 200 sonuçlar ayrıca '{args.output}' dosyasına yazılacak.\n")

    session = create_session(args.workers)
    found_count = 0
    checked_count = 0

    try:
        with open(args.output, "a", encoding="utf-8") as out_file:
            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                # Bellek şişmesini önlemek için parça parça (batch) gönderim
                batch_size = 2000
                for batch_start in range(args.start, args.end + 1, batch_size):
                    batch_end = min(batch_start + batch_size - 1, args.end)
                    futures = [
                        executor.submit(check_id, session, item_id, args.timeout)
                        for item_id in range(batch_start, batch_end + 1)
                    ]

                    for future in as_completed(futures):
                        item_id, url, status = future.result()
                        checked_count += 1

                        if status == 200:
                            found_count += 1
                            with print_lock:
                                print(f"[200] {url}")
                            out_file.write(f"{url}\n")
                            out_file.flush()

                        if checked_count % 5000 == 0:
                            with print_lock:
                                print(f"İlerleme: {checked_count}/{total} kontrol edildi, {found_count} adet 200 bulundu.")
    except KeyboardInterrupt:
        print("\nKullanıcı tarafından durduruldu.")
    finally:
        session.close()

    print(f"\nTamamlandı. Kontrol edilen: {checked_count}/{total}, Bulunan (200): {found_count}")


if __name__ == "__main__":
    main()
