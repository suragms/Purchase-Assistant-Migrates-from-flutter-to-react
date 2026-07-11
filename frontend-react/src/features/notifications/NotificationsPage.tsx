"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { LuBell } from "react-icons/lu";

const NotificationsPage = () => {
  return (
    <div className="p-4">
      <Card>
        <CardHeader className="flex flex-row items-center gap-4">
          <div className="bg-blue-100 p-2 rounded-lg">
            <LuBell className="h-6 w-6 text-blue-600" />
          </div>
          <div>
            <CardTitle>Notifications</CardTitle>
            <CardDescription>View and manage your notifications</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="p-4 border rounded-lg">
              <p className="text-sm text-gray-500">No notifications yet</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default NotificationsPage;