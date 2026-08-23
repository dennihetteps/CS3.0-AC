import base64
import hashlib
import io
import os
import secrets
import flet as ft
from PIL import Image


# --- 1. КРИПТОГРАФИЧЕСКАЯ ЛОГИКА (ВАШ АЛГОРИТМ ЧИСТОГО ШИФРОВАНИЯ) ---
class SecureChromaShift:

    def __init__(self, key_phrase: str):
        # Превращаем ключ в SHA-256 хэш (32 байта)
        self.key_hash = hashlib.sha256(key_phrase.encode("utf-8")).digest()

    def encrypt(self, text: str) -> list:
        plain_bytes = text.encode("utf-8")
        cipher_bytes = []

        # Для борьбы с частотным анализом замешиваем индекс символа в хэш ключа
        for idx, b in enumerate(plain_bytes):
            mix = hashlib.sha256(
                self.key_hash + idx.to_bytes(4, byteorder="big")
            ).digest()
            key_byte = mix[0]  # Извлекаем байт гаммы
            cipher_bytes.append(b ^ key_byte)
        return cipher_bytes

    def generate_image_bytes(
        self, cipher_bytes: list, stripe_width=20, img_height=200
    ) -> bytes:
        img_width = len(cipher_bytes) * stripe_width
        img = Image.new("RGB", (img_width, img_height))
        pixels = img.load()

        for i, c_byte in enumerate(cipher_bytes):
            r = c_byte
            g = secrets.randbelow(256)
            b = secrets.randbelow(256)

            # Попиксельная отрисовка полосы ChromaShift
            for x_offset in range(stripe_width):
                x = i * stripe_width + x_offset
                for y in range(img_height):
                    pixels[x, y] = (r, g, b)

        # Переводим сгенерированную картинку в байтовый поток памяти
        img_buffer = io.BytesIO()
        img.save(img_buffer, format="PNG")
        return img_buffer.getvalue()

    def decrypt_uploaded_image(self, img_bytes_data, stripe_width=20) -> str:
        try:
            # Чтение картинки напрямую из оперативной памяти
            img = Image.open(io.BytesIO(img_bytes_data)).convert("RGB")
            img_width, img_height = img.size
            pixels = img.load()

            num_stripes = img_width // stripe_width
            cipher_bytes = []

            for i in range(num_stripes):
                x = i * stripe_width + (stripe_width // 2)
                y = img_height // 2
                r, g, b = pixels[x, y]
                cipher_bytes.append(r)

            decrypted_bytes = bytearray()
            for idx, c_byte in enumerate(cipher_bytes):
                mix = hashlib.sha256(
                    self.key_hash + idx.to_bytes(4, byteorder="big")
                ).digest()
                key_byte = mix[0]
                decrypted_bytes.append(c_byte ^ key_byte)

            return decrypted_bytes.decode("utf-8")
        except Exception:
            return "Ошибка: Неверный секретный ключ или структура пикселей была нарушена!"


# --- 2. ИНТЕРФЕЙС ПРИЛОЖЕНИЯ ПОД СТИЛЬ ИКОНКИ (ФИОЛЕТОВАЯ ГАММА UI) ---
def main(page: ft.Page):
    page.title = "ChromaShift 3.0"
    page.theme_mode = ft.ThemeMode.DARK
    page.window_width = 450
    page.window_height = 800
    page.scroll = ft.ScrollMode.AUTO

    # Кастомизация темы приложения под цветовую палитру предоставленного логотипа
    page.theme = ft.Theme(
        color_scheme=ft.ColorScheme(
            primary=ft.colors.INDIGO_400,
            secondary=ft.colors.PURPLE_400,
            surface=ft.colors.GREY_900,
        )
    )

    # Поля ввода текстовых данных
    key_input = ft.TextField(
        label="Секретный ключ (Пароль)",
        password=True,
        can_reveal_password=True,
        border_color=ft.colors.INDIGO_400,
        icon=ft.icons.KEY,
    )
    text_to_encrypt = ft.TextField(
        label="Текст сообщения для шифрования",
        multiline=True,
        max_lines=4,
        hint_text="Введите секретную информацию для скрытия...",
    )
    decrypted_output = ft.TextField(
        label="Результат дешифрования текста",
        read_only=True,
        multiline=True,
        border_color=ft.colors.PURPLE_300,
    )

    # Превью сгенерированной картинки
    img_preview = ft.Image(visible=False, height=180, fit=ft.ImageFit.CONTAIN)

    # Буфер для хранения считанных с диска байт
    selected_file_bytes = None

    # Действие при нажатии кнопки "Зашифровать"
    def on_encrypt_click(e):
        if not key_input.value or not text_to_encrypt.value:
            page.open(
                ft.SnackBar(ft.Text("Ошибка: Заполните ключ и текст сообщения!"))
            )
            return

        engine = SecureChromaShift(key_input.value)
        cipher_blocks = engine.encrypt(text_to_encrypt.value)
        raw_png = engine.generate_image_bytes(cipher_blocks)

        # Вывод картинки на экран без сохранения на жесткий диск через base64 строку
        b64_str = base64.b64encode(raw_png).decode("utf-8")
        img_preview.src_base64 = b64_str
        img_preview.visible = True

        # Локальное сохранение файла в директорию документов
        try:
            with open("chromashift_msg.png", "wb") as f:
                f.write(raw_png)
            page.open(
                ft.SnackBar(
                    ft.Text(
                        "[+] Успешно зашифровано! Файл chromashift_msg.png сохранен."
                    )
                )
            )
        except Exception as err:
            page.open(
                ft.SnackBar(ft.Text(f"Ошибка сохранения файла на диск: {err}"))
            )

        page.update()

    # Асинхронный перехватщик файлов из галереи или проводника Android
    def on_file_picked_result(e: ft.FilePickerResultEvent):
        nonlocal selected_file_bytes
        if e.files:
            file_info = e.files
            with open(file_info.path, "rb") as target_file:
                selected_file_bytes = target_file.read()

            file_picker_btn.text = f"Выбран файл: {file_info.name}"
            file_picker_btn.icon = ft.icons.FILE_DOWNLOAD_DONE
            page.update()

    native_picker = ft.FilePicker(on_result=on_file_picked_result)
    page.overlay.append(native_picker)

    # Действие при нажатии кнопки "Расшифровать"
    def on_decrypt_click(e):
        if not key_input.value:
            page.open(ft.SnackBar(ft.Text("Введите пароль дешифрования!")))
            return
        if selected_file_bytes is None:
            page.open(
                ft.SnackBar(ft.Text("Сначала выберите файл зашифрованного фото!"))
            )
            return

        engine = SecureChromaShift(key_input.value)
        clear_text = engine.decrypt_uploaded_image(selected_file_bytes)
        decrypted_output.value = clear_text
        page.update()

    file_picker_btn = ft.ElevatedButton(
        "Выбрать файл-шифр из галереи",
        icon=ft.icons.IMAGE_SEARCH,
        on_click=lambda _: native_picker.pick_files(
            allow_multiple=False, allowed_extensions=["png", "jpg", "jpeg"]
        ),
    )

    # Генерация вкладок
    tabs_menu = ft.Tabs(
        selected_index=0,
        animation_duration=200,
        tabs=[
            ft.Tab(
                text="ШИФРОВАНИЕ",
                content=ft.Column(
                    [
                        ft.Container(height=10),
                        text_to_encrypt,
                        ft.ElevatedButton(
                            "Зашифровать текст в фото",
                            icon=ft.icons.VIRTUAL_LOCK_OUTLINED,
                            on_click=on_encrypt_click,
                            style=ft.ButtonStyle(bgcolor=ft.colors.INDIGO_900),
                        ),
                        img_preview,
                    ],
                    spacing=15,
                ),
            ),
            ft.Tab(
                text="РАСШИФРОВКА",
                content=ft.Column(
                    [
                        ft.Container(height=10),
                        file_picker_btn,
                        ft.ElevatedButton(
                            "Расшифровать выбранное фото",
                            icon=ft.icons.LOCK_OPEN,
                            on_click=on_decrypt_click,
                            style=ft.ButtonStyle(bgcolor=ft.colors.PURPLE_900),
                        ),
                        decrypted_output,
                    ],
                    spacing=15,
                ),
            ),
        ],
        expand=1,
    )

    # Позиционирование элементов на экране смартфона
    page.add(
        ft.Container(height=10),
        ft.Row(
            [
                ft.Icon(ft.icons.VPN_KEY_ROUNDED, color=ft.colors.INDIGO_400),
                ft.Text("ChromaShift 3.0", size=24, bold=True),
            ],
            alignment=ft.MainAxisAlignment.CENTER,
        ),
        ft.Row(
            [
                ft.Text(
                    "Один из самых сильнейших алгоритмов шифрования",
                    size=12,
                    color=ft.colors.GREY_400,
                )
            ],
            alignment=ft.MainAxisAlignment.CENTER,
        ),
        ft.Container(height=10),
        key_input,
        ft.Divider(height=2, color=ft.colors.GREY_800),
        tabs_menu,
    )


if __name__ == "__main__":
    ft.app(target=main)
