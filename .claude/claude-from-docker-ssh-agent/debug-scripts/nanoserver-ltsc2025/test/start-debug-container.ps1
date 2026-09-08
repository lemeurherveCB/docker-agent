docker rm -f ssh-debug-test 2>$null
docker run --detach --tty --name ssh-debug-test --publish-all `
  jenkins/ssh-agent:nanoserver-ltsc2025-jdk21 `
  "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAvnRN27LdPPQq2OH3GiFFGWX/SH5TCPVePLR21ngMFV8nAthXgYrFkRi/t+Wafe3ByTu2XYUDlXHKGIPIoAKo4gz5dIjUFfoac1ZuCDIbEiqPEjkk4tkfc2qr/BnIZsOYQi4Mbu+Z40VZEsAQU7eBinnZaHE1qGMHjS1xfrRtp2rdeO1EBz92FJ8dfnkUnohTXo3qPVSFGIPbh7UKEoKcyCosRO1P41iWD1rVsH1SLLXYAh2t49L7IPiplg09Dep6H47LyQVbxU9eXY8yMtUrRuwEk9IUX/IqpxNhk5hngHPP3JjsP0hyyrYSPkZlbs3izd9kk3y09Wn/ElHidiEk0Q=="
Start-Sleep 10
docker ps -a
docker port ssh-debug-test 22
