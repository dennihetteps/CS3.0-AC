import hashlib
import os
import secrets
from PIL import Image
import io

# Импортируем инструменты для отображения графики и создания кнопок прямо в ячейке Colab
from IPython.display import display, Image as IPImage
from google.colab import files

class SecureChromaShift:
    def __init__(self, key_phrase: str):
        # Превращаем ключ в SHA-256 хэш (32 байта)
        self.key_hash = hashlib.sha256(key_phrase.encode('utf-8')).digest()
        
    def encrypt(self, text: str) -> list:
        plain_bytes = text.encode('utf-8')
        cipher_bytes = []
        
        # Для борьбы с частотным анализом замешиваем индекс символа в хэш ключа
        for idx, b in enumerate(plain_bytes):
            mix = hashlib.sha256(self.key_hash + idx.to_bytes(4, byteorder='big')).digest()
            key_byte = mix[0] # Берем байт гаммы
            cipher_bytes.append(b ^ key_byte)
            
        return cipher_bytes

    def generate_and_show_image(self, cipher_bytes: list, stripe_width=20, img_height=200):
        img_width = len(cipher_bytes) * stripe_width
        img = Image.new("RGB", (img_width, img_height))
        pixels = img.load()
        
        for i, c_byte in enumerate(cipher_bytes):
            r = c_byte
            g = secrets.randbelow(256)
            b = secrets.randbelow(256)
            
            # Отрисовка полосы
            for x_offset in range(stripe_width):
                x = i * stripe_width + x_offset
                for y in range(img_height):
                    pixels[x, y] = (r, g, b)
                    
        # Сохраняем изображение в байтовый буфер в памяти, чтобы сразу показать на экране
        img_buffer = io.BytesIO()
        img.save(img_buffer, format='PNG')
        img_bytes = img_buffer.getvalue()
        
        print("\n[+] Текст зашифрован! Ваше секретное фото сообщения:")
        # Выводим картинку прямо под ячейку с кодом
        display(IPImage(data=img_bytes))
        
        # Также сохраняем файл локально на случай, если пользователь захочет его скачать
        img.save("chromashift_msg.png")
        print("💡 Фотография также сохранена в файлы сессии под именем: chromashift_msg.png")

    def decrypt_uploaded_image(self, img_bytes_data, stripe_width=20) -> str:
        # Открываем изображение напрямую из загруженных пользователем байт
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
            mix = hashlib.sha256(self.key_hash + idx.to_bytes(4, byteorder='big')).digest()
            key_byte = mix[0]
            decrypted_bytes.append(c_byte ^ key_byte)
            
        try:
            return decrypted_bytes.decode('utf-8')
        except Exception:
            return "Ошибка: Неверный секретный ключ или файл был поврежден при передаче!"

# --- ИНТЕРФЕЙС CHROMASHIFT v3.0 ---
print("=== АКТИВАЦИЯ ЗАЩИЩЕННОГО CHROMASHIFT v3.0 ===")
action = input("Выберите действие: 1 (Зашифровать текст в фото) или 2 (Расшифровать фото): ")

if action == "1":
    key = input("Введите секретный ключ (пароль): ")
    msg = input("Введите секретный текст: ")
    
    cipher = SecureChromaShift(key)
    bytes_data = cipher.encrypt(msg)
    cipher.generate_and_show_image(bytes_data)
    
elif action == "2":
    key = input("Введите секретный ключ для расшифровки: ")
    
    print("\n[*] Нажмите на кнопку ниже, чтобы загрузить секретную фотографию:")
    uploaded = files.upload() # Появляется удобная интерактивная кнопка для выбора файла
    
    if uploaded:
        # Берем байты первого загруженного файла
        file_name = list(uploaded.keys())[0]
        file_bytes = uploaded[file_name]
        
        cipher = SecureChromaShift(key)
        result = cipher.decrypt_uploaded_image(file_bytes)
        print(f"\n[*] Результат расшифровки:\n{result}")
    else:
        print("Ошибка: Файл не был загружен.")

