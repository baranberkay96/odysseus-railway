# ntfy push notifications for Odysseus reminders and alerts, with users and
# the Odysseus publish token provisioned from Railway variables.
FROM binwiederhier/ntfy:v2.30.0@sha256:8563a39da2f5a47360618b2ab9200239c76b37f4145f6d627d9ab4368abd23f0

COPY railway-start.sh /usr/local/bin/railway-start.sh
RUN chmod 0755 /usr/local/bin/railway-start.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
