Name:           perfmon
Version:        1.1.0
Release:        1%{?dist}
Summary:        System performance monitor (CPU/Memory/Disk IO/Network)
License:        MIT
BuildArch:      noarch
Requires:       sysstat gawk zip

%description
perfmon is a lightweight system performance monitoring tool that records
CPU, memory, and disk IO metrics per-process using vmstat, iostat, and pidstat.
Logs are stored with timestamps and automatically rotated.

%prep
# no source tarball; files provided directly

%build
# nothing to build

%install
install -d %{buildroot}/opt/perfmon/bin
install -d %{buildroot}/opt/perfmon/log
install -d %{buildroot}/etc/perfmon
install -d %{buildroot}/usr/lib/systemd/system
install -d %{buildroot}/usr/bin

install -m 0755 %{_sourcedir}/perfmon-collector.sh %{buildroot}/opt/perfmon/bin/perfmon-collector.sh
install -m 0755 %{_sourcedir}/perfmon-save.sh      %{buildroot}/usr/bin/perfmon-save
install -m 0644 %{_sourcedir}/perfmon.conf          %{buildroot}/etc/perfmon/perfmon.conf
install -m 0644 %{_sourcedir}/perfmon.service       %{buildroot}/usr/lib/systemd/system/perfmon.service

%files
%dir /opt/perfmon
%dir /opt/perfmon/bin
%dir /opt/perfmon/log
%dir /etc/perfmon
/opt/perfmon/bin/perfmon-collector.sh
/usr/bin/perfmon-save
%config(noreplace) /etc/perfmon/perfmon.conf
/usr/lib/systemd/system/perfmon.service

%post
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl enable perfmon.service >/dev/null 2>&1 || :
systemctl start perfmon.service >/dev/null 2>&1 || :

%preun
systemctl stop perfmon.service >/dev/null 2>&1 || :
systemctl disable perfmon.service >/dev/null 2>&1 || :

%postun
systemctl daemon-reload >/dev/null 2>&1 || :

%changelog
* Fri Feb 20 2026 hijiri - 1.1.0-1
- Skip boot average (first report) for vmstat/iostat/pidstat/mpstat/sar
- Add vmstat column header to log output
- Add mpstat collector (per-CPU utilization breakdown)
- Add sar -n DEV collector (network interface statistics)
- Add top collector (system overview + process list in batch mode)
- Fix iostat gawk: device lines were skipped due to /^[a-zA-Z]/ matching lowercase
- Fix pidstat gawk: data lines were output twice due to missing next

* Fri Feb 20 2026 hijiri - 1.0.0-1
- Initial release
