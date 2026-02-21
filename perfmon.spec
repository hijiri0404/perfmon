Name:           perfmon
Version:        1.3.0
Release:        1%{?dist}
Summary:        System performance monitor (CPU/Memory/Disk IO/Network)
License:        MIT
BuildArch:      noarch
Requires:       sysstat gawk zip lsof

%description
perfmon is a lightweight system performance monitoring tool that records
CPU, memory, disk IO, network, and kernel metrics with per-process granularity.
All log entries are prefixed with timestamps and automatically rotated daily.

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
* Sat Feb 21 2026 hijiri - 1.3.0-1
- top: add -c (full command path + args) and -w 512 (prevent line truncation)
- pidstat: add -l (full command line with arguments)
- dstate: use ps args instead of comm (full command path + arguments)
- Add connections collector (ss -tunap: all sockets with process info incl. LISTEN)
- Add lsof collector (lsof -n -P: open files per process)
- Add lsof to RPM Requires

* Sat Feb 21 2026 hijiri - 1.2.0-1
- Fix: date rotation deadlock caused by parent shell holding pipe read-end fd
  (stop_collectors now uses pkill -P $$ to terminate all child processes)
- Fix: top log now prefixes each line with timestamp (consistent with other logs)
- Add meminfo collector (/proc/meminfo: Slab, HugePages, Dirty, CommitLimit, etc.)
- Add netstat collector (ss -s: TCP connection state summary)
- Add df collector (disk capacity and inode usage per filesystem)
- Add fdcount collector (/proc/sys/fs/file-nr: system-wide fd count)
- Add dstate collector (D-state processes with PID/PPID/wchan for I/O hang diagnosis)
- Add dmesg collector (kernel messages via dmesg -w: OOM, disk errors, hw faults)
- Add log compression: rotated logs are gzip-compressed on date change and startup
- Update perfmon-save to include both .log and .log.gz files

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
