# Basic bspwm setup for Ubuntu Server

Script cài môi trường bspwm tối thiểu trên Ubuntu Server, chỉ gồm Xorg,
`bspwm`, `sxhkd` và `xterm`. Script không cài display manager hay thay đổi
cấu hình mạng của máy.

## Cài đặt

```bash
chmod +x install-bspwm.sh
sudo ./install-bspwm.sh
```

Sau khi cài xong, đăng nhập ở TTY bằng user thường và chạy `startx`.

Script mặc định cấu hình cho user đã gọi `sudo`. Nếu đang đăng nhập bằng root,
hãy chỉ định user thường:

```bash
sudo ./install-bspwm.sh --user ten_user
```

Nhấn phím Windows/Super bên trái để mở terminal.
