# 켜봄 브랜드 에셋

실제 앱 아이콘은 사용자 Mac의 `~/Downloads/app_icon_real.png` 또는
`~/Downloads/AppIcons*/app_icon_real.png`에서 가져옵니다.

```bash
bash tools/apply_kyeobom_icons.sh
```

스크립트를 실행하면 이 폴더에 `app_icon_real.png`가 복사되고
Android의 `mipmap-*/ic_launcher.png` 및 iOS의
`AppIcon.appiconset` 파일도 생성됩니다.

원본 PNG는 사용자 컴퓨터에만 있으므로 GitHub 원격 저장소에
실제 이미지 바이너리를 임의로 생성하여 올리지 않습니다.
